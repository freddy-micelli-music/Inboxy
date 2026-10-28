import SwiftUI
import WebKit

enum GmailAttachmentRouting {
    static func attachmentURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { return false }
        if host == "mail-attachment.googleusercontent.com" || host.hasSuffix("-mail-attachment.googleusercontent.com") { return true }
        guard GmailNavigationRules.mailboxPage(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.queryItems?.contains { $0.name == "view" && $0.value == "att" } == true
    }
    static func blobFromGmail(_ url: URL) -> Bool {
        guard url.scheme == "blob", let origin = URL(string: String(url.absoluteString.dropFirst(5))) else { return false }
        return origin.scheme == "https" && origin.host == "mail.google.com" && origin.user == nil && origin.password == nil && origin.port == nil
    }
    static func downloadResponse(_ response: URLResponse, canShow: Bool) -> Bool {
        let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let kind = disposition.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        return !canShow || kind == "attachment" || (response.url.map { attachmentURL($0) || blobFromGmail($0) } == true && response.mimeType?.lowercased() != "text/html")
    }
}

struct AttachmentFileStore {
    struct Staging { let directory: URL; let file: URL; let name: String }
    var destination: URL
    static func safeName(_ suggested: String) -> String {
        let leaf = (suggested.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        var value = leaf.components(separatedBy: .controlCharacters).joined().replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix(".") { value.removeFirst() }
        if value.isEmpty { value = "Pièce jointe" }
        while value.utf8.count > 220 { value.removeLast() }
        return value.isEmpty ? "Pièce jointe" : value
    }
    func stage(_ suggested: String) throws -> Staging {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Inboxy-attachment-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let name = Self.safeName(suggested)
        return Staging(directory: directory, file: directory.appendingPathComponent(name), name: name)
    }
    func finish(_ staging: Staging) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let ext = (staging.name as NSString).pathExtension
        let stem = ext.isEmpty ? staging.name : (staging.name as NSString).deletingPathExtension
        for index in 1...1000 {
            let name = index == 1 ? staging.name : stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let url = destination.appendingPathComponent(name)
            do {
                // moveItem refuses an existing destination, including a symbolic link.
                try FileManager.default.moveItem(at: staging.file, to: url)
                discard(staging)
                return url
            } catch {
                let issue = error as NSError
                if issue.domain == NSCocoaErrorDomain && issue.code == NSFileWriteFileExistsError { continue }
                throw error
            }
        }
        throw AerisError.message("Trop de fichiers portent déjà ce nom dans Téléchargements.")
    }
    func discard(_ staging: Staging) { try? FileManager.default.removeItem(at: staging.directory) }
}

@MainActor final class AttachmentDownloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = AttachmentDownloads()
    @Published private(set) var activeCount = 0
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var lastError: String?
    private struct Transfer {
        let download: WKDownload
        let source: WKWebView
        let navigation: (any WKNavigationDelegate)?
        var staging: AttachmentFileStore.Staging?
    }
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    private var popups: [ObjectIdentifier: (WKWebView, WebDelegate)] = [:]
    private let store: AttachmentFileStore
    init(destination: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        store = AttachmentFileStore(destination: destination)
    }
    func adopt(_ download: WKDownload, from web: WKWebView) {
        transfers[ObjectIdentifier(download)] = Transfer(download: download, source: web, navigation: web.navigationDelegate)
        download.delegate = self
        activeCount = transfers.count; lastError = nil
        popups[ObjectIdentifier(web)] = nil
    }
    func popup(configuration: WKWebViewConfiguration, inboxURL: URL) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configuration)
        let key = ObjectIdentifier(web)
        let delegate = WebDelegate(inboxURL: inboxURL) { [weak self] status in
            if let error = status.error { self?.lastError = "Téléchargement : " + error }
        }
        delegate.downloads = self
        delegate.popupFinished = { [weak self] in self?.popups[key] = nil }
        web.navigationDelegate = delegate; web.uiDelegate = delegate
        popups[key] = (web, delegate)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if let popup = self?.popups.removeValue(forKey: key) {
                popup.0.stopLoading()
                self?.lastError = "Le téléchargement n’a pas démarré. Réessayez depuis la pièce jointe dans Gmail."
            }
        }
        return web
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        guard transfers[key] != nil else { completionHandler(nil); return }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            failed(download, message: "Le serveur a refusé la pièce jointe (\(http.statusCode)). Réessayez depuis le message Gmail.")
            completionHandler(nil); return
        }
        do {
            let staging = try store.stage(suggestedFilename)
            transfers[key]?.staging = staging
            completionHandler(staging.file)
        } catch { failed(download, message: error.localizedDescription); completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        defer { activeCount = transfers.count }
        guard let staging = transfer.staging else { return }
        do { lastSavedURL = try store.finish(staging); lastError = nil }
        catch {
            // Keep completed bytes if Downloads becomes unavailable; offer Save As.
            let panel = NSSavePanel(); panel.nameFieldStringValue = staging.name
            panel.message = "Impossible d’enregistrer dans Téléchargements. Choisissez un autre emplacement."
            panel.begin { response in
                defer { self.store.discard(staging) }
                guard response == .OK, let url = panel.url else { self.lastError = "Enregistrement de la pièce jointe annulé."; return }
                do {
                    // A save panel explicitly confirms replacement of an existing file.
                    if FileManager.default.fileExists(atPath: url.path) {
                        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging.file)
                    } else { try FileManager.default.moveItem(at: staging.file, to: url) }
                    self.lastSavedURL = url; self.lastError = nil
                } catch { self.lastError = "Pièce jointe non enregistrée : " + error.localizedDescription }
            }
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { failed(download, message: error.localizedDescription) }
    private func failed(_ download: WKDownload, message: String) {
        if let staging = transfers.removeValue(forKey: ObjectIdentifier(download))?.staging { store.discard(staging) }
        activeCount = transfers.count; lastError = "Pièce jointe non téléchargée : " + message
    }
}

enum GmailNavigationRules {
    static func mailboxPage(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host?.lowercased() == "mail.google.com" && url?.path.hasPrefix("/mail/") == true
    }
    static func externalPage(_ url: URL, from source: URL?, activated: Bool, newWindow: Bool = false) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
        if mailboxPage(url) { return false }
        if mailboxPage(source), activated || newWindow || !googleHost(url.host ?? "") { return true }
        return (activated || newWindow) && !googleHost(url.host ?? "")
    }
    // Google's published supported_domains list, reviewed 22 October 2026.
    // Match a registrable domain or an actual subdomain, never a substring.
    private static let googleDomains = Set("""
    google.com google.ad google.ae google.com.af google.com.ag google.al google.am google.co.ao google.com.ar google.as google.at google.com.au google.az google.ba google.com.bd google.be google.bf google.bg google.com.bh google.bi google.bj google.com.bn google.com.bo google.com.br google.bs google.bt google.co.bw google.by google.com.bz google.ca google.cd google.cf google.cg google.ch google.ci google.co.ck google.cl google.cm google.cn google.com.co google.co.cr google.com.cu google.cv google.com.cy google.cz google.de google.dj google.dk google.dm google.com.do google.dz google.com.ec google.ee google.com.eg google.es google.com.et google.fi google.com.fj google.fm google.fr google.ga google.ge google.gg google.com.gh google.com.gi google.gl google.gm google.gr google.com.gt google.gy google.com.hk google.hn google.hr google.ht google.hu google.co.id google.ie google.co.il google.im google.co.in google.iq google.is google.it google.je google.com.jm google.jo google.co.jp google.co.ke google.com.kh google.ki google.kg google.co.kr google.com.kw google.kz google.la google.com.lb google.li google.lk google.co.ls google.lt google.lu google.lv google.com.ly google.co.ma google.md google.me google.mg google.mk google.ml google.com.mm google.mn google.com.mt google.mu google.mv google.mw google.com.mx google.com.my google.co.mz google.com.na google.com.ng google.com.ni google.ne google.nl google.no google.com.np google.nr google.nu google.co.nz google.com.om google.com.pa google.com.pe google.com.pg google.com.ph google.com.pk google.pl google.pn google.com.pr google.ps google.pt google.com.py google.com.qa google.ro google.ru google.rw google.com.sa google.com.sb google.sc google.se google.com.sg google.sh google.si google.sk google.com.sl google.sn google.so google.sm google.sr google.st google.com.sv google.td google.tg google.co.th google.com.tj google.tl google.tm google.tn google.to google.com.tr google.tt google.com.tw google.co.tz google.com.ua google.co.ug google.co.uk google.com.uy google.co.uz google.com.vc google.co.ve google.co.vi google.com.vn google.vu google.ws google.rs google.co.za google.co.zm google.co.zw google.cat googleusercontent.com gstatic.com
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    // Google's sign-in chain also visits these exact account endpoints.
    // https://support.google.com/chrome/a/answer/6334001
    // Chromium: IsValidGaiaSigninRedirectOrResponseURL (one_click_signin_helper.cc).
    // Do not allow arbitrary YouTube/Blogger pages or subdomains here.
    private static let accountServiceHosts: Set<String> = ["accounts.youtube.com", "accounts.blogger.com"]

    static func googleHost(_ raw: String) -> Bool {
        let host = raw.lowercased()
        return accountServiceHosts.contains(host) || googleDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func internalDocument(_ url: URL) -> Bool {
        url.scheme == "about" && ["blank", "srcdoc"].contains(url.path)
    }
    static func cancelled(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
    static func cookieRedirectInterrupted(_ error: NSError, currentURL: URL?) -> Bool {
        guard error.domain == "WebKitErrorDomain", error.code == 102 else { return false }
        let failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:)) ?? currentURL
        guard let url = failedURL, url.scheme == "https", let host = url.host?.lowercased(), host.hasPrefix("accounts."), googleHost(host) else { return false }
        return url.path == "/CheckCookie" || url.path == "/CheckCookie/"
    }
}

enum GmailPresentation {
    static func navigationScript(visible: Bool) -> String {
        "(() => { const visible = " + (visible ? "true" : "false") + ";" + #"""
        if (location.protocol !== 'https:' || location.hostname !== 'mail.google.com' || !location.pathname.startsWith('/mail/')) return;
        const root = document.documentElement;
        if (!root) return;
        let style = document.getElementById('inboxy-gmail-navigation');
        if (!style) {
            style = document.createElement('style'); style.id = 'inboxy-gmail-navigation';
            style.textContent = `
                html[data-inboxy-folders-hidden="true"] .bkK { margin-left: 0 !important; width: auto !important; }
                html[data-inboxy-folders-hidden="true"] .bkK .AO,
                html[data-inboxy-folders-hidden="true"] .bkK .aeF { width: auto !important; }
                html[data-inboxy-folders-hidden="true"] .aeN,
                html[data-inboxy-folders-hidden="true"] [role="navigation"],
                html[data-inboxy-folders-hidden="true"] [role="banner"] [aria-label="Menu principal"],
                html[data-inboxy-folders-hidden="true"] [role="banner"] [aria-label="Main menu"] { display: none !important; }
            `;
            (document.head || root).appendChild(style);
        }
        root.setAttribute('data-inboxy-folders-hidden', visible ? 'false' : 'true');
        window.dispatchEvent(new Event('resize'));
        """# + "})();"
    }
}

struct GmailNavigationItem: Equatable, Identifiable {
    let title: String
    let fragment: String
    var id: String { fragment }
    var symbol: String {
        switch fragment.split(separator: "/").first {
        case "label": return "tag"
        case "category": return "tray.2"
        case "drafts": return "doc"
        case "spam": return "exclamationmark.octagon"
        case "snoozed": return "clock"
        case "scheduled": return "calendar"
        case "imp", "important": return "flag"
        default: return "tray.full"
        }
    }
    @MainActor func url(account: MailAccount) -> URL {
        var target = URLComponents(url: WebSessions.gmailURL(account: account), resolvingAgainstBaseURL: false)!
        target.percentEncodedFragment = fragment
        return target.url!
    }
}

struct GmailMailboxState: Equatable {
    var unread: Int?
    var folder: MailFolder?
    var avatarURL: URL?
    var avatarRect: CGRect?
    var navigationItems: [GmailNavigationItem] = []
}

enum GmailMailboxMetadata {
    static func navigationItems(_ raw: Any?) -> [GmailNavigationItem] {
        guard let entries = raw as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return entries.prefix(5000).compactMap { entry in
            guard let name = entry["title"] as? String, let href = entry["href"] as? String,
                  let url = URL(string: href), GmailNavigationRules.mailboxPage(url),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let fragment = components.percentEncodedFragment,
                  let section = components.fragment?.split(separator: "/").first,
                  ["label", "category", "drafts", "snoozed", "scheduled", "all", "spam", "imp", "important", "chats"].contains(String(section)),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(fragment).inserted else { return nil }
            return GmailNavigationItem(title: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)), fragment: fragment)
        }
    }

    static func avatarURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              (host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com") || ["lh3.google.com", "lh4.google.com", "lh5.google.com", "lh6.google.com"].contains(host)) else { return nil }
        return url
    }

    static func folder(url: URL?) -> MailFolder? {
        guard let url, url.scheme == "https", url.host == "mail.google.com", url.path.hasPrefix("/mail/") else { return nil }
        let route = (url.fragment?.removingPercentEncoding ?? "").replacingOccurrences(of: "+", with: " ")
        let section = route.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        switch section {
        case "inbox", "category": return .inbox
        case "starred": return .starred
        case "sent": return .sent
        case "trash": return .trash
        case "search": return route.range(of: "(^|[ /])is:unread($|[ /])", options: .regularExpression) != nil ? .unread : nil
        default: return nil
        }
    }
    static func titleCount(_ title: String, url: URL?) -> Int? {
        guard folder(url: url) == .inbox,
              let regex = try? NSRegularExpression(pattern: "^(?:Inbox|Bo[îi]te de r[ée]ception)\\s*(?:\\(([0-9][0-9 ,.  ]*)\\))?\\s*-", options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) else { return nil }
        guard let range = Range(match.range(at: 1), in: title) else { return 0 }
        return Int(title[range].filter(\.isNumber))
    }
}

@MainActor final class GmailMailboxTracker: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "AerisMailbox")
    var navigationVisible: Bool?
    private weak var web: WKWebView?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var state = GmailMailboxState()
    private var domCountKnown = false
    private let changed: (GmailMailboxState) -> Void
    init(changed: @escaping (GmailMailboxState) -> Void) { self.changed = changed }
    func attach(_ web: WKWebView) {
        self.web = web
        urlObservation = web.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.readLocation() }
        }
        titleObservation = web.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.readLocation() }
        }
    }
    private func readLocation() {
        guard let web else { return }
        var next = state
        next.folder = GmailMailboxMetadata.folder(url: web.url)
        if web.url?.host != "mail.google.com" { next.unread = nil; domCountKnown = false }
        else if !domCountKnown, let count = GmailMailboxMetadata.titleCount(web.title ?? "", url: web.url) { next.unread = count }
        publish(next)
    }
    private func publish(_ next: GmailMailboxState) {
        guard next != state else { return }
        state = next; changed(next)
    }
    func install(on web: WKWebView) {
        guard web.url?.scheme == "https", web.url?.host == "mail.google.com", web.url?.path.hasPrefix("/mail/") == true else { return }
        readLocation()
        if let visible = navigationVisible {
            web.callAsyncJavaScript(GmailPresentation.navigationScript(visible: visible), arguments: [:], in: nil, in: Self.world) { _ in }
        }
        web.callAsyncJavaScript(Self.observerScript, arguments: [:], in: nil, in: Self.world) { _ in }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "mail.google.com",
              let web, web.url?.host == "mail.google.com", let body = message.body as? [String: Any] else { return }
        var next = state
        next.folder = GmailMailboxMetadata.folder(url: web.url)
        if body["navigation"] != nil { next.navigationItems = GmailMailboxMetadata.navigationItems(body["navigation"]) }
        if let number = body["unread"] as? NSNumber {
            let count = number.intValue
            guard count >= 0 && count <= 100_000_000, number.doubleValue == Double(count), CFGetTypeID(number) != CFBooleanGetTypeID() else { return }
            next.unread = count; domCountKnown = true
        }
        if let avatar = GmailMailboxMetadata.avatarURL(body["avatar"] as? String) {
            next.avatarURL = avatar
            if let rect = body["avatarRect"] as? [Double], rect.count == 4, rect.allSatisfy(\.isFinite),
               rect[0] >= 0, rect[1] >= 0, rect[2] > 0, rect[2] <= 128, rect[3] > 0, rect[3] <= 128 {
                next.avatarRect = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            }
        }
        publish(next)
    }
    // Read only Gmail's navigation counter and Google account photo URL. No message bodies, inputs,
    // passwords, or authentication documents are read or modified.
    static let observerScript = #"""
    if (location.protocol !== 'https:' || location.hostname !== 'mail.google.com' || !location.pathname.startsWith('/mail/')) return;
    if (window.__aerisMailboxObserver) return;
    window.__aerisMailboxObserver = true;
    let pending = 0;
    let last = null;
    const report = () => {
        pending = 0;
        const links = Array.from(document.querySelectorAll('a[href]')).filter(a => {
            try { return new URL(a.href).hash === '#inbox' && (a.getClientRects().length > 0 || document.documentElement.getAttribute('data-inboxy-folders-hidden') === 'true'); } catch { return false; }
        });
        const inbox = links.find(a => {
            const label = ((a.getAttribute('aria-label') || '') + ' ' + (a.textContent || '')).trim();
            return label.length > 0 && !/^gmail$/i.test(label.trim()) && (a.closest('[role="navigation"],nav') || /inbox|r[ée]ception/i.test(label));
        });
        let count = null;
        if (inbox) {
            const parent = inbox.parentElement;
            const row = parent && parent.querySelectorAll('a[href]').length <= 1 ? parent : inbox;
            const label = [inbox.getAttribute('aria-label') || '', inbox.getAttribute('title') || '', row.textContent || ''].join(' ');
            const numbers = label.match(/[0-9][0-9\s,.  ]*/g);
            if (numbers && !label.includes('+')) {
                const digits = numbers[numbers.length - 1].replace(/[^0-9]/g, '');
                count = Number(digits);
            } else if (!numbers) { count = 0; }
        }
        const accountButtons = Array.from(document.querySelectorAll('[aria-label]')).filter(a =>
            /Google\s+Account|Compte\s+Google/i.test(a.getAttribute('aria-label') || ''));
        const candidates = accountButtons.flatMap(a => Array.from(a.querySelectorAll('img'))).concat(
            Array.from(document.querySelectorAll('a[href*="accounts.google.com"] img, [role="banner"] img')));
        const photo = candidates.find(image => {
            try { const u = new URL(image.currentSrc || image.src);
                return u.protocol === 'https:' && (u.hostname === 'googleusercontent.com' || u.hostname.endsWith('.googleusercontent.com') || /^lh[3-6]\.google\.com$/.test(u.hostname)) && image.getClientRects().length > 0;
            } catch { return false; }
        });
        const rect = photo && photo.getBoundingClientRect();
        const navigation = Array.from(document.querySelectorAll('.aeN a[href], [role="navigation"] a[href]')).map(a => ({
            title: (a.textContent || a.getAttribute('title') || a.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim(), href: a.href
        }));
        const value = { unread: Number.isSafeInteger(count) && count >= 0 && count <= 100000000 ? count : null,
            avatar: photo ? (photo.currentSrc || photo.src) : null,
            avatarRect: rect ? [rect.x, rect.y, rect.width, rect.height] : null, navigation };
        const signature = JSON.stringify(value) + location.hash;
        if (signature !== last) { last = signature; window.webkit.messageHandlers.aerisMailbox.postMessage(value); }
    };
    const schedule = () => { if (!pending) pending = setTimeout(report, 180); };
    new MutationObserver(schedule).observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['aria-label', 'title', 'src']});
    addEventListener('hashchange', schedule);
    addEventListener('popstate', schedule);
    setInterval(schedule, 15000);
    report();
    """#
}

@MainActor final class WebSessions: ObservableObject {
    struct Entry { let web: WKWebView; let delegate: WebDelegate; let tracker: GmailMailboxTracker }
    struct Status { var loading = false; var host = "mail.google.com"; var error: String? }
    @Published var states: [UUID: Status] = [:]
    @Published private(set) var accountPhotos: [UUID: NSImage] = [:]
    private var capturedPhotoURLs: [UUID: URL] = [:]
    @Published private(set) var mailboxes: [UUID: GmailMailboxState] = [:]
    var mailboxDidChange: ((UUID, GmailMailboxState) -> Void)?
    @Published private(set) var pendingAttachments: [UUID: [URL]] = [:]
    @Published private(set) var attachmentNotices: [UUID: String] = [:]
    var mailtoRequested: ((URL) -> Void)?
    private var cache: [UUID: Entry] = [:]
    private var recency: [UUID] = []
    private var calendars: [UUID: CalendarWindow] = [:]
    @Published private(set) var upcomingAppointments: [UUID: CalendarTickerState] = [:]
    private var appointmentCheckedAt: [UUID: Date] = [:]
    private var appointmentProbes: [UUID: CalendarUpcomingProbe] = [:]
    func refreshNextAppointment(account: MailAccount) async {
        if let checked = appointmentCheckedAt[account.id], Date().timeIntervalSince(checked) < 55 { return }
        guard appointmentProbes[account.id] == nil else { return }
        if upcomingAppointments[account.id] == nil { upcomingAppointments[account.id] = .loading }
        let probe = CalendarUpcomingProbe()
        appointmentProbes[account.id] = probe
        defer { appointmentProbes[account.id] = nil }
        do {
            let state = try await probe.read(account: account)
            try Task.checkCancellation()
            upcomingAppointments[account.id] = state
            appointmentCheckedAt[account.id] = Date()
        } catch is CancellationError { }
        catch { upcomingAppointments[account.id] = .unavailable }
    }
    @Published private(set) var zoomLevels: [UUID: Double] = [:]
    var focusedCalendarID: UUID? { calendars.first(where: { $0.value.window === NSApp.keyWindow })?.key }
    static func boundedZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(2, max(0.5, (value * 10).rounded() / 10))
    }
    func zoom(for account: MailAccount) -> Double {
        let stored = UserDefaults.standard.object(forKey: "webZoom." + account.id.uuidString) as? Double ?? 1
        return zoomLevels[account.id] ?? Self.boundedZoom(stored)
    }
    func setZoom(_ value: Double, account: MailAccount) {
        let level = Self.boundedZoom(value)
        zoomLevels[account.id] = level
        UserDefaults.standard.set(level, forKey: "webZoom." + account.id.uuidString)
        cache[account.id]?.web.pageZoom = level
        calendars[account.id]?.web.pageZoom = level
    }
    static func calendarURL(account: MailAccount) -> URL {
        var url = URLComponents(string: "https://calendar.google.com/calendar/u/0/r")!
        url.queryItems = [URLQueryItem(name: "authuser", value: account.email)]
        return url.url!
    }
    func showCalendar(account: MailAccount, appointment: CalendarAppointment? = nil) {
        if let calendar = calendars[account.id] {
            if let appointment {
                calendar.navigation.pendingCalendarEventID = appointment.eventID
                calendar.web.load(URLRequest(url: CalendarUpcomingProbe.agendaURL(account: account)))
            }
            calendar.window.makeKeyAndOrderFront(nil)
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        config.applicationNameForUserAgent = Self.compatibilityApplicationName
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let url = appointment == nil ? Self.calendarURL(account: account) : CalendarUpcomingProbe.agendaURL(account: account)
        let delegate = WebDelegate(inboxURL: url) { _ in }
        delegate.composeMailto = { [weak self] url in self?.mailtoRequested?(url) }
        delegate.pendingCalendarEventID = appointment?.eventID
        let web = WKWebView(frame: .zero, configuration: config)
        web.pageZoom = zoom(for: account)
        web.navigationDelegate = delegate; web.uiDelegate = delegate
        web.allowsBackForwardNavigationGestures = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Agenda · " + account.email
        window.minSize = NSSize(width: 600, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.center()
        let calendar = CalendarWindow(window: window, web: web, navigation: delegate)
        calendar.closed = { [weak self] in self?.calendars[account.id] = nil }
        window.delegate = calendar
        calendars[account.id] = calendar
        window.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: url))
    }
    private var badgeProbes: [UUID: GmailUnreadProbe] = [:]
    let capacity = 3
    // WKWebView's generated engine/OS portion remains intact. Add compatibility
    // product tokens for the installed system Safari and identify Aeris explicitly.
    static var compatibilityApplicationName: String {
        let aerisVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        guard let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
              let safari = Bundle(url: safariURL),
              let version = safari.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else {
            return "Inboxy/" + aerisVersion
        }
        // Safari and WKWebView use the same system engine. Safari's public
        // compatibility product version is frozen at 605.1.15 on macOS.
        return "Version/\(version) Safari/605.1.15 Inboxy/\(aerisVersion)"
    }
    static func gmailURL(account: MailAccount, fragment: String = "inbox") -> URL {
        var url = URLComponents(string: "https://mail.google.com/mail/u/0/")!
        url.queryItems = [URLQueryItem(name: "authuser", value: account.email)]
        url.fragment = fragment
        return url.url!
    }
    func view(for account: MailAccount) -> WKWebView {
        recency.removeAll { $0 == account.id }; recency.append(account.id)
        if let entry = cache[account.id] { return entry.web }
        while cache.count >= capacity, let oldest = recency.first(where: { cache[$0] != nil && $0 != account.id }) {
            cache[oldest]?.web.stopLoading(); cache.removeValue(forKey: oldest); recency.removeAll { $0 == oldest }
        }
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = Self.compatibilityApplicationName
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let tracker = GmailMailboxTracker { [weak self] state in
            guard let self else { return }
            self.mailboxes[account.id] = state
            self.mailboxDidChange?(account.id, state)
            if let url = state.avatarURL, let rect = state.avatarRect,
               self.capturedPhotoURLs[account.id] != url, let web = self.cache[account.id]?.web {
                let zoom = web.pageZoom
                let area = CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
                guard web.bounds.contains(area) else { return }
                self.capturedPhotoURLs[account.id] = url
                let snapshot = WKSnapshotConfiguration()
                snapshot.rect = area; snapshot.snapshotWidth = 68
                web.takeSnapshot(with: snapshot) { [weak self] photo, _ in
                    if let photo { self?.accountPhotos[account.id] = photo }
                    else { self?.capturedPhotoURLs[account.id] = nil }
                }
            }
        }
        let navigationVisible = false
        tracker.navigationVisible = navigationVisible
        config.userContentController.addUserScript(WKUserScript(source: GmailPresentation.navigationScript(visible: navigationVisible), injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: GmailMailboxTracker.world))
        config.userContentController.add(tracker, contentWorld: GmailMailboxTracker.world, name: "aerisMailbox")
        let delegate = WebDelegate(inboxURL: Self.gmailURL(account: account)) { [weak self] status in self?.states[account.id] = status }
        let web = WKWebView(frame: .zero, configuration: config)
        delegate.mailboxTracker = tracker
        delegate.composeMailto = { [weak self] url in self?.mailtoRequested?(url) }
        delegate.takeAttachments = { [weak self] multiple in
            guard let self, let files = self.pendingAttachments[account.id], !files.isEmpty else { return nil }
            let chosen = multiple ? files : Array(files.prefix(1))
            self.pendingAttachments[account.id] = Array(files.dropFirst(chosen.count))
            self.attachmentNotices[account.id] = "Fichiers transmis à Gmail. Vérifiez leur présence dans le brouillon avant l’envoi."
            return chosen
        }
        web.navigationDelegate = delegate; web.uiDelegate = delegate
        tracker.attach(web)
        web.pageZoom = zoom(for: account)
        web.allowsBackForwardNavigationGestures = true
        cache[account.id] = Entry(web: web, delegate: delegate, tracker: tracker)
        web.load(URLRequest(url: Self.gmailURL(account: account)))
        return web
    }
    func reload(account: MailAccount) {
        let web = view(for: account)
        let current = web.url.flatMap { $0.host == "mail.google.com" && $0.path.hasPrefix("/mail/") ? $0 : nil }
        web.load(URLRequest(url: current ?? Self.gmailURL(account: account)))
    }
    func navigate(account: MailAccount, folder: MailFolder) {
        let fragment: String
        switch folder { case .inbox: fragment = "inbox"; case .unread: fragment = "search/in:inbox is:unread"; case .starred: fragment = "starred"; case .sent: fragment = "sent"; case .trash: fragment = "trash" }
        view(for: account).load(URLRequest(url: Self.gmailURL(account: account, fragment: fragment)))
    }
    func navigate(account: MailAccount, item: GmailNavigationItem) {
        view(for: account).load(URLRequest(url: item.url(account: account)))
    }
    func compose(account: MailAccount, request: MailComposeRequest) {
        pendingAttachments[account.id] = request.files
        attachmentNotices[account.id] = nil
        view(for: account).load(URLRequest(url: request.gmailURL(account: account)))
    }
    func clearAttachments(account: MailAccount) {
        pendingAttachments[account.id] = nil; attachmentNotices[account.id] = nil
    }
    func attachmentNoticesDismiss(account: MailAccount) { attachmentNotices[account.id] = nil }
    func attachPending(account: MailAccount) {
        let web = view(for: account)
        guard web.url?.host == "mail.google.com", web.url?.path.hasPrefix("/mail/") == true else { return }
        web.callAsyncJavaScript(#"""
        const labels = ['Joindre des fichiers', 'Joindre un fichier', 'Attach files'];
        const button = Array.from(document.querySelectorAll('[role="button"],button')).find(e =>
            labels.some(label => e.getAttribute('aria-label') === label || e.getAttribute('data-tooltip') === label || e.getAttribute('title') === label));
        if (button) { button.click(); return true; }
        return false;
        """#, arguments: [:], in: nil, in: GmailMailboxTracker.world) { [weak self] _ in
            guard let self, !(self.pendingAttachments[account.id] ?? []).isEmpty else { return }
            self.attachmentNotices[account.id] = "Dans le message Gmail, cliquez sur le trombone « Joindre des fichiers » pour joindre les fichiers sélectionnés."
        }
    }
    func checkUnread(account: MailAccount) async throws -> Int {
        let probe = GmailUnreadProbe()
        badgeProbes[account.id] = probe
        defer { badgeProbes[account.id] = nil }
        return try await probe.read(account: account)
    }
    func cancelBadgeChecks() {
        for probe in badgeProbes.values { probe.cancel() }
    }
    func remove(_ id: UUID) async throws {
        appointmentProbes[id]?.cancel(); appointmentProbes[id] = nil
        upcomingAppointments[id] = nil; appointmentCheckedAt[id] = nil
        calendars[id]?.window.close(); calendars[id] = nil
        accountPhotos[id] = nil; capturedPhotoURLs[id] = nil
        zoomLevels[id] = nil
        UserDefaults.standard.removeObject(forKey: "webZoom." + id.uuidString)
        pendingAttachments[id] = nil; attachmentNotices[id] = nil
        badgeProbes[id]?.cancel()
        badgeProbes[id] = nil
        cache[id]?.web.stopLoading(); cache.removeValue(forKey: id); recency.removeAll { $0 == id }; states[id] = nil; mailboxes[id] = nil
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        if identifiers.contains(id) {
            // SwiftUI detaches the selected WKWebView on the next layout pass.
            // Wait asynchronously and retry a bounded number of times if WebKit
            // still considers its persistent store in use.
            for attempt in 0..<4 {
                try await Task.sleep(nanoseconds: 100_000_000 * UInt64(attempt + 1))
                do { try await WKWebsiteDataStore.remove(forIdentifier: id); return }
                catch { if attempt == 3 { throw error } }
            }
        }
    }
    func suspendAll() {
        for probe in appointmentProbes.values { probe.cancel() }
        appointmentProbes.removeAll()
        for entry in cache.values { entry.web.stopLoading() }
        cache.removeAll(); recency.removeAll()
        for calendar in Array(calendars.values) { calendar.window.close() }
        calendars.removeAll()
    }
}

// Retain the navigation delegate while the window is open; release the profile on close.
@MainActor private final class CalendarWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let web: WKWebView
    let navigation: WebDelegate
    var closed: (() -> Void)?
    init(window: NSWindow, web: WKWebView, navigation: WebDelegate) {
        self.window = window; self.web = web; self.navigation = navigation
    }
    func windowWillClose(_ notification: Notification) {
        web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil
        window.contentView = nil
        closed?()
    }
}

// A bounded, temporary background view reads Gmail's own inbox counter using
// the same persistent profile. It never navigates or evicts the visible view.
@MainActor private final class GmailUnreadProbe {
    private var web: WKWebView?
    private var delegate: WebDelegate?
    private var tracker: GmailMailboxTracker?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Int, Error>?

    func read(account: MailAccount) async throws -> Int {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
                config.applicationNameForUserAgent = WebSessions.compatibilityApplicationName
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                let tracker = GmailMailboxTracker { [weak self] state in
                    if let count = state.unread { self?.finish(.success(count)) }
                }
                config.userContentController.add(tracker, contentWorld: GmailMailboxTracker.world, name: "aerisMailbox")
                let delegate = WebDelegate(inboxURL: WebSessions.gmailURL(account: account)) { [weak self] status in
                    if status.error != nil { self?.finish(.failure(AerisError.message("Relevé indisponible. Ouvrez ce compte pour vérifier sa connexion."))) }
                    else if !status.loading, status.host.hasPrefix("accounts.") {
                        self?.finish(.failure(AerisError.message("Connexion à renouveler : ouvrez ce compte.")))
                    }
                }
                let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: config)
                self.web = web; self.delegate = delegate; self.tracker = tracker
                delegate.mailboxTracker = tracker
                web.navigationDelegate = delegate
                tracker.attach(web)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                    catch { return }
                    self?.finish(.failure(AerisError.message("Gmail ne répond pas au relevé. Nouvelle tentative au prochain cycle.")))
                }
                web.load(URLRequest(url: WebSessions.gmailURL(account: account), cachePolicy: .reloadIgnoringLocalCacheData))
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Int, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        web?.stopLoading()
        web?.navigationDelegate = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "aerisMailbox", contentWorld: GmailMailboxTracker.world)
        web = nil; delegate = nil; tracker = nil
        continuation.resume(with: result)
    }
}

@MainActor final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    var downloads = AttachmentDownloads.shared
    var popupFinished: (() -> Void)?
    var pendingCalendarEventID: String?
    weak var mailboxTracker: GmailMailboxTracker?
    var composeMailto: ((URL) -> Void)?
    var takeAttachments: ((Bool) -> [URL]?)?
    private var status = WebSessions.Status()
    private let changed: (WebSessions.Status) -> Void
    private let inboxURL: URL
    private var activeNavigation: WKNavigation?
    private var retriedCookieRedirect = false
    private var downloadNavigationPending = false
    init(inboxURL: URL, changed: @escaping (WebSessions.Status) -> Void) { self.inboxURL = inboxURL; self.changed = changed }
    private func fail(_ message: String) { status.loading = false; status.error = message; changed(status) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme?.lowercased() == "mailto" {
            composeMailto?(url); decisionHandler(.cancel); return
        }
        let attachment = GmailAttachmentRouting.attachmentURL(url) || GmailAttachmentRouting.blobFromGmail(url)
        if action.shouldPerformDownload, attachment || GmailNavigationRules.mailboxPage(webView.url) {
            downloadNavigationPending = true
            decisionHandler(.download); return
        }
        if attachment { decisionHandler(.allow); return }
        if GmailNavigationRules.externalPage(url, from: webView.url, activated: action.navigationType == .linkActivated) {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        if GmailNavigationRules.internalDocument(url) { decisionHandler(.allow); return }
        guard let host = url.host?.lowercased(), url.scheme == "https" else {
            if action.targetFrame?.isMainFrame != false { fail("Cette adresse ne peut pas être ouverte dans Gmail intégré. Cliquez sur Réessayer pour revenir à Gmail.") }
            decisionHandler(.cancel); return
        }
        // First-party Gmail sign-in is displayed as provided by Google. The app
        // identifies its Safari compatibility and Aeris product name; no cookies
        // are imported and no scripts are injected into sign-in pages.
        if host == "accounts.google.com", url.path.contains("/o/oauth") {
            fail("Ce parcours OAuth ne peut pas être effectué dans la vue intégrée. La connexion API reste disponible dans Ajouter un compte → Autre méthode.")
            decisionHandler(.cancel); return
        }
        let google = GmailNavigationRules.googleHost(host)
        if action.targetFrame?.isMainFrame != false && !google {
            if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            else { fail("Cette connexion redirige vers un fournisseur externe (\(host)). La connexion SSO intégrée n’est pas prise en charge dans ce prototype.") }
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if GmailAttachmentRouting.downloadResponse(response.response, canShow: response.canShowMIMEType) {
            downloadNavigationPending = true
            decisionHandler(.download)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads.adopt(download, from: webView); popupFinished?()
        downloadNavigationPending = true
        status.loading = false; status.error = nil; changed(status)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads.adopt(download, from: webView); popupFinished?()
        downloadNavigationPending = true
        status.loading = false; status.error = nil; changed(status)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
        downloadNavigationPending = false
        status.loading = true; status.error = nil; status.host = webView.url?.host ?? "mail.google.com"; changed(status)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { status.host = webView.url?.host ?? status.host; changed(status) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !stale(navigation) else { return }
        status.loading = false; status.error = nil; status.host = webView.url?.host ?? status.host; changed(status)
        mailboxTracker?.install(on: webView)
        if let eventID = pendingCalendarEventID, webView.url?.scheme == "https", webView.url?.host == "calendar.google.com" {
            pendingCalendarEventID = nil
            webView.callAsyncJavaScript(#"""
            return await new Promise(resolve => {
                let tries = 0;
                const timer = setInterval(() => {
                    const chip = Array.from(document.querySelectorAll('[data-eventid][role="button"]')).find(e => e.getAttribute('data-eventid') === eventID);
                    if (chip) { clearInterval(timer); chip.scrollIntoView({block:'center'}); chip.click(); resolve(true); }
                    else if (++tries >= 50) { clearInterval(timer); resolve(false); }
                }, 300);
            });
            """#, arguments: ["eventID": eventID], in: nil, in: GmailMailboxTracker.world) { result in
                if case .success(let value) = result, value as? Bool == true { return }
                let alert = NSAlert(); alert.messageText = "Rendez-vous à vérifier"
                alert.informativeText = "Le rendez-vous n’a pas pu être retrouvé dans la liste chargée. L’Agenda du compte est ouvert pour le retrouver."
                if let window = webView.window { alert.beginSheetModal(for: window) { _ in } }
            }
        }
    }
    private func stale(_ navigation: WKNavigation?) -> Bool {
        guard let activeNavigation, let navigation else { return false }
        return activeNavigation !== navigation
    }
    private func handleFailure(_ error: Error, navigation: WKNavigation?, web: WKWebView) {
        guard !stale(navigation) else { return }
        let nsError = error as NSError
        if GmailNavigationRules.cancelled(nsError) { return }
        if downloadNavigationPending, nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        popupFinished?()
        // Retry only this known cookie-check interruption, once per web-view lifetime.
        // Start from Gmail instead of resubmitting a sign-in form or clearing cookies.
        if status.error == nil, !retriedCookieRedirect, GmailNavigationRules.cookieRedirectInterrupted(nsError, currentURL: web.url) {
            retriedCookieRedirect = true
            DispatchQueue.main.async { [weak self, weak web] in
                guard let self, let web, !self.stale(navigation) else { return }
                web.load(URLRequest(url: self.inboxURL))
            }
            return
        }
        // Keep the useful explanation of a policy rejection, rather than replacing
        // it with WebKit's generic "Frame load interrupted" callback.
        if status.error == nil {
            let message = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
                ? "Google a interrompu une redirection. Cliquez sur Réessayer pour reprendre la connexion."
                : error.localizedDescription
            fail(message)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleFailure(error, navigation: navigation, web: webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleFailure(error, navigation: navigation, web: webView) }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if url.scheme?.lowercased() == "mailto" { composeMailto?(url); return nil }
        if action.shouldPerformDownload || GmailAttachmentRouting.attachmentURL(url) || GmailAttachmentRouting.blobFromGmail(url) || (GmailNavigationRules.internalDocument(url) && GmailNavigationRules.mailboxPage(webView.url)) {
            return downloads.popup(configuration: configuration, inboxURL: inboxURL)
        }
        if GmailNavigationRules.externalPage(url, from: webView.url, activated: action.navigationType == .linkActivated, newWindow: true) {
            NSWorkspace.shared.open(url); return nil
        }
        guard url.scheme == "https", let host = url.host else { return nil }
        if GmailNavigationRules.googleHost(host) { webView.load(action.request) }
        else { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard GmailNavigationRules.mailboxPage(webView.url), frame.securityOrigin.protocol == "https", frame.securityOrigin.host == "mail.google.com" else {
            completionHandler(nil); return
        }
        if let files = takeAttachments?(parameters.allowsMultipleSelection) {
            do { completionHandler(try MailComposeRequest.readableFiles(files)) }
            catch { fail(error.localizedDescription); completionHandler(nil) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.prompt = "Joindre"
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
        } else { panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) } }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("La vue Gmail s’est interrompue. Cliquez sur Actualiser pour la recharger.") }
    func webViewDidClose(_ webView: WKWebView) { popupFinished?() }
}

struct GmailWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct IntegratedGmailView: View {
    let account: MailAccount
    @ObservedObject var sessions: WebSessions
    @ObservedObject private var downloads = AttachmentDownloads.shared
    var showNative: (() -> Void)?
    var body: some View {
        let status = sessions.states[account.id] ?? WebSessions.Status()
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(Palette.accent)
                    .help("Connexion à " + status.host)
                    .accessibilityLabel("Connexion à " + status.host)
                Spacer(minLength: 8)
                Button {
                    if let url = downloads.lastSavedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    else { NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) }
                } label: {
                    Label(downloads.activeCount > 0 ? "\(downloads.activeCount)" : "", systemImage: "arrow.down.circle")
                }.buttonStyle(.plain).help(downloads.lastSavedURL.map { "Afficher dans le Finder : " + $0.lastPathComponent } ?? "Ouvrir Téléchargements")
                    .accessibilityLabel("Téléchargements")
                    .accessibilityValue(downloads.activeCount > 0 ? "\(downloads.activeCount) en cours" : (downloads.lastSavedURL?.lastPathComponent ?? "Aucun fichier téléchargé"))
                Button { sessions.setZoom(1, account: account) } label: {
                    Label("\(Int((sessions.zoom(for: account) * 100).rounded())) %", systemImage: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit().frame(minWidth: 62, alignment: .trailing)
                }.buttonStyle(.plain)
                    .help("Zoom du contenu · ⌘− / ⌘+ · Cliquer pour revenir à 100 %")
                    .accessibilityLabel("Zoom du contenu : \(Int((sessions.zoom(for: account) * 100).rounded())) pour cent")
                Slider(value: Binding(get: { sessions.zoom(for: account) }, set: { sessions.setZoom($0, account: account) }), in: 0.5...2, step: 0.1)
                    .frame(width: 130).controlSize(.small).tint(Palette.accent)
                    .accessibilityLabel("Ajuster le zoom du contenu")
                    .accessibilityValue("\(Int((sessions.zoom(for: account) * 100).rounded())) pour cent")
                    .help("Glissez pour réduire ou agrandir le contenu de 50 à 200 %")
                if status.loading { ProgressView().controlSize(.small) }
                Button { sessions.reload(account: account) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Recharger Gmail")
                if let showNative { Button("Lecture native", action: showNative).font(.system(size: 11)) }
            }.padding(.horizontal, 18).padding(.vertical, 10)
                .foregroundStyle(.white.opacity(0.8)).environment(\.colorScheme, .dark)
                .background(Palette.navigationBackground)
            if let error = status.error {
                HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle"); Text(error).font(.system(size: 12)); Spacer(); Button("Réessayer") { sessions.reload(account: account) } }.padding(14).background(.orange.opacity(0.12))
            }
            if let error = downloads.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(10)
            }
            if let files = sessions.pendingAttachments[account.id], !files.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "paperclip")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(files.count) fichier(s) à joindre").font(.system(size: 12, weight: .semibold))
                        Text(files.map(\.lastPathComponent).joined(separator: ", ")).font(.system(size: 11)).lineLimit(2)
                    }
                    Spacer()
                    Button("Joindre les fichiers") { sessions.attachPending(account: account) }
                    Button("Annuler") { sessions.clearAttachments(account: account) }.buttonStyle(.plain)
                }.padding(12).background(Palette.accent.opacity(0.1))
            }
            if let notice = sessions.attachmentNotices[account.id] {
                HStack { Text(notice).font(.system(size: 11)); Spacer(); Button { sessions.attachmentNoticesDismiss(account: account) } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(10).background(Palette.accent.opacity(0.06))
            }
            GmailWebView(web: sessions.view(for: account)).id(account.id)
        }
    }
}

struct CalendarAppointment: Equatable {
    let eventID: String
    let title: String
    let start: Date
    let allDay: Bool
    func isUpcoming(at now: Date) -> Bool {
        allDay ? Calendar.autoupdatingCurrent.startOfDay(for: start) >= Calendar.autoupdatingCurrent.startOfDay(for: now) : start >= now
    }
    var announcement: String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "fr_FR")
        date.dateFormat = allDay ? "EEEE d MMMM · 'Journée entière'" : "EEEE d MMMM · HH:mm"
        return "PROCHAIN RDV  •  " + date.string(from: start) + "  •  " + title
    }
}

enum CalendarAppointmentMetadata {
    // Calendar's rendered date key packs year offset, month and day. Validate
    // every component by a date round trip; never parse a message/event title.
    static func dateComponents(key: Int) -> DateComponents? {
        guard key > 0, key < 200_000 else { return nil }
        let components = DateComponents(year: 1970 + (key >> 9), month: (key >> 5) & 15, day: key & 31)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: components), calendar.component(.year, from: date) == components.year,
              calendar.component(.month, from: date) == components.month, calendar.component(.day, from: date) == components.day else { return nil }
        return components
    }
    static func appointments(_ raw: Any?, now: Date = Date()) -> [CalendarAppointment] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return rows.prefix(1000).compactMap { row in
            guard let id = row["id"] as? String, id.range(of: "^[A-Za-z0-9_=\\-]{1,1024}$", options: .regularExpression) != nil,
                  let name = row["title"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let key = row["dayKey"] as? NSNumber, CFGetTypeID(key) != CFBooleanGetTypeID(), key.doubleValue == Double(key.intValue),
                  var components = dateComponents(key: key.intValue), let label = row["label"] as? String,
                  row["cancelled"] as? Bool != true else { return nil }
            let allDay = label.range(of: "jour entier|toute la journ[ée]e|all.day", options: [.regularExpression, .caseInsensitive]) != nil
            var calendar = Calendar(identifier: .gregorian)
            if allDay { calendar.timeZone = .autoupdatingCurrent }
            else {
                guard let zoneName = row["timeZone"] as? String, let zone = TimeZone(identifier: zoneName) else { return nil }
                calendar.timeZone = zone
                // Use the browser's local time zone, matching the Calendar UI;
                // Calendar's current app ignores the legacy ctz URL parameter.
                let prefix = String(label.split(separator: ",", maxSplits: 1).first ?? "")
                guard let regex = try? NSRegularExpression(pattern: "(?:^|[^0-9])([0-9]{1,2})(?:(?::|h)([0-9]{2})\\s*([ap]m)?|\\s*([ap]m))", options: .caseInsensitive),
                      let match = regex.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
                      let hr = Range(match.range(at: 1), in: prefix), var hour = Int(prefix[hr]) else { return nil }
                let minute = Range(match.range(at: 2), in: prefix).flatMap { Int(prefix[$0]) } ?? 0
                guard minute < 60 else { return nil }
                if let ar = Range(match.range(at: 3), in: prefix) ?? Range(match.range(at: 4), in: prefix) {
                    guard (1...12).contains(hour) else { return nil }
                    hour = hour % 12 + (prefix[ar].lowercased() == "pm" ? 12 : 0)
                }
                guard hour < 24 else { return nil }
                components.hour = hour; components.minute = minute
            }
            guard let start = calendar.date(from: components) else { return nil }
            let event = CalendarAppointment(eventID: id, title: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)), start: start, allDay: allDay)
            guard event.isUpcoming(at: now), seen.insert(id).inserted else { return nil }
            return event
        }.sorted { $0.start == $1.start ? $0.eventID < $1.eventID : $0.start < $1.start }
    }
}

enum CalendarTickerState {
    case loading, ready(CalendarAppointment), empty, unavailable
    var appointment: CalendarAppointment? { if case .ready(let event) = self { return event }; return nil }
    var message: String {
        switch self {
        case .loading: return "Agenda · Actualisation…"
        case .ready(let event): return event.announcement
        case .empty: return "Aucun prochain RDV affiché · Ouvrir l’Agenda"
        case .unavailable: return "Agenda à vérifier · Cliquer pour ouvrir"
        }
    }
}

@MainActor private final class CalendarUpcomingProbe {
    private var web: WKWebView?
    private var navigation: WebDelegate?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<CalendarTickerState, Error>?
    private var collecting = false
    private var expectedEmail = ""
    static func agendaURL(account: MailAccount) -> URL {
        var url = URLComponents(string: "https://calendar.google.com/calendar/u/0/r/agenda")!
        url.queryItems = [URLQueryItem(name: "authuser", value: account.email), URLQueryItem(name: "hl", value: "fr")]
        return url.url!
    }
    func read(account: MailAccount) async throws -> CalendarTickerState {
        expectedEmail = account.email
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
                config.applicationNameForUserAgent = WebSessions.compatibilityApplicationName
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                let url = Self.agendaURL(account: account)
                let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: config)
                let navigation = WebDelegate(inboxURL: url) { [weak self] status in
                    guard let self, !status.loading else { return }
                    if status.error != nil || status.host.hasPrefix("accounts.") { self.finish(.success(.unavailable)) }
                    else if status.host == "calendar.google.com" { self.collect() }
                }
                self.web = web; self.navigation = navigation
                web.navigationDelegate = navigation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                    self?.finish(.success(.unavailable))
                }
                web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func collect() {
        guard !collecting, let web, web.url?.scheme == "https", web.url?.host == "calendar.google.com" else { return }
        collecting = true
        web.callAsyncJavaScript(Self.script, arguments: ["expectedEmail": expectedEmail], in: nil, in: GmailMailboxTracker.world) { [weak self] result in
            guard let self else { return }
            guard case .success(let object) = result, let body = object as? [String: Any], body["ready"] as? Bool == true else {
                self.finish(.success(.unavailable)); return
            }
            let rows = body["events"] as? [[String: Any]] ?? []
            if let first = CalendarAppointmentMetadata.appointments(rows).first { self.finish(.success(.ready(first))) }
            else if rows.isEmpty, body["empty"] as? Bool != true { self.finish(.success(.unavailable)) }
            else if !rows.isEmpty && CalendarAppointmentMetadata.appointments(rows, now: .distantPast).isEmpty {
                self.finish(.success(.unavailable))
            } else { self.finish(.success(.empty)) }
        }
    }
    private func finish(_ result: Result<CalendarTickerState, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        web?.stopLoading(); web?.navigationDelegate = nil
        web = nil; navigation = nil
        continuation.resume(with: result)
    }
    // Read only the schedule's event chips: title, accessible time, date key and
    // event identifier. No descriptions, attendees, credentials or private APIs.
    static let script = #"""
    if (location.protocol !== 'https:' || location.hostname !== 'calendar.google.com') return {ready:false};
    return await new Promise(resolve => {
        let last = '', stable = 0, tries = 0;
        const timer = setInterval(() => {
            const identities = Array.from(document.querySelectorAll('a[aria-label]')).map(e => e.getAttribute('aria-label') || '').filter(label => /Google\s+Account|Compte\s+Google/i.test(label) && label.includes('@'));
            if (identities.length && !identities.some(label => label.toLowerCase().includes(expectedEmail.toLowerCase()))) {
                clearInterval(timer); resolve({ready:false}); return;
            }
            const chips = Array.from(document.querySelectorAll('[data-eventid][role="button"]'));
            const events = chips.slice(0,1000).map(e => {
                const day = e.closest('[data-datekey]');
                const label = e.getAttribute('aria-label') || '';
                return {id:e.getAttribute('data-eventid') || '', title:(e.textContent || '').trim(),
                    label, timeZone:Intl.DateTimeFormat().resolvedOptions().timeZone, dayKey:day ? Number(day.getAttribute('data-datekey')) : null,
                    cancelled: /annul[ée]|refus[ée]|cancelled|canceled|declined/i.test(label) || getComputedStyle(e).textDecorationLine.includes('line-through')};
            });
            const empty = Array.from(document.querySelectorAll('[role="main"], [role="grid"]')).some(e => /Aucun [ée]v[ée]nement|No events/i.test(e.textContent || ''));
            const signature = JSON.stringify(events);
            if (signature === last) stable++; else { stable=0; last=signature; }
            if ((events.length || empty) && stable >= 3) { clearInterval(timer); resolve({ready:true,events,empty}); }
            else if (++tries >= 40) { clearInterval(timer); resolve({ready:false}); }
        }, 400);
    });
    """#
}
