import SwiftUI
import AppKit
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var accounts: [MailAccount] = []
    @Published var selectedID: UUID?
    @Published var folder: MailFolder = .inbox
    @Published var search = ""
    @Published var accountSearch = ""
    @Published var messages: [MailMessage] = []
    @Published var selectedMessageID: String?
    @Published var unread: [UUID: Int] = [:]
    @Published private(set) var checkingBadges: Set<UUID> = []
    @Published private(set) var badgeCheckedAt: [UUID: Date] = [:]
    @Published private(set) var badgeErrors: [UUID: String] = [:]
    @Published private(set) var webFolders: [UUID: MailFolder] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var loading = false
    @Published var loadingBody = false
    @Published var nextPage: String?
    @Published var alert: String?
    @Published var showAdd = false
    @Published var showSwitcher = false
    @Published var webMode = false
    @Published var connected = false
    @Published var connecting = false
    @Published var notificationStatus = "Non activées"
    @Published var composeRequest: MailComposeRequest?
    let automaticUpdater = AutomaticUpdater()
    @Published var accountTransferInProgress = false
    @Published private(set) var updateState: AppUpdateState = .idle
    @Published var updatePrompt: AppUpdateOffer?
    let programVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private var checkedUpdatesAtStartup = false
    @AppStorage("gmailFoldersExpanded") var gmailFoldersExpanded = false
    func toggleGmailNavigation() { gmailFoldersExpanded.toggle() }
    @AppStorage("navigationPlacement") var navigationPlacement = "left"
    var placement: NavigationPlacement { NavigationPlacement(rawValue: navigationPlacement) ?? .left }
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("oauthClientID") var clientID = ""
    let webSessions = WebSessions()
    let auth = GoogleAuth()
    let api = GmailAPI()
    private let persistence: AccountPersistence
    private let updateLookup: (String) async throws -> AppUpdateOffer?
    private var loadTask: Task<Void, Never>?
    private var bodyTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var bodyGeneration = UUID()
    private var generation = UUID()
    @Published private(set) var removing: Set<UUID> = []
    private var hydrated: Set<String> = []
    private var polling = false
    private var badgeGeneration = UUID()

    private var zoomAccount: MailAccount? {
        if let id = webSessions.focusedCalendarID { return accounts.first(where: { $0.id == id }) }
        return selectedAccount
    }
    var canZoom: Bool { zoomAccount.map { !$0.isDemo && (webSessions.focusedCalendarID != nil || webMode || $0.usesWeb) } ?? false }
    func changeZoom(_ delta: Double) {
        guard canZoom, let account = zoomAccount else { return }
        webSessions.setZoom(webSessions.zoom(for: account) + delta, account: account)
    }
    func resetZoom() {
        guard canZoom, let account = zoomAccount else { return }
        webSessions.setZoom(1, account: account)
    }

    var visibleAccounts: [MailAccount] { accounts }
    var selectedAccount: MailAccount? { visibleAccounts.first { $0.id == selectedID } }
    var selectedMessage: MailMessage? { messages.first { $0.id == selectedMessageID } }
    var filteredAccounts: [MailAccount] {
        visibleAccounts.filter { accountSearch.isEmpty || ($0.name + $0.email).localizedCaseInsensitiveContains(accountSearch) }
    }
    var totalUnread: Int { visibleAccounts.reduce(0) { $0 + (unread[$1.id] ?? 0) } }
    var usingWeb: Bool { selectedAccount.map { !$0.isDemo && ($0.usesWeb || webMode) } ?? false }
    var selectedInboxCount: Int? {
        guard let account = selectedAccount else { return nil }
        if usingWeb { return unread[account.id] ?? webSessions.mailboxes[account.id]?.unread }
        return unread[account.id]
    }
    func folderSelected(_ value: MailFolder) -> Bool {
        usingWeb ? selectedID.flatMap { webFolders[$0] } == value : folder == value
    }
    func openFolder(_ value: MailFolder) {
        folder = value
        if let account = selectedAccount, usingWeb {
            webSessions.navigate(account: account, folder: value)
        } else { load() }
    }
    private func syncMailbox(_ id: UUID, _ state: GmailMailboxState) {
        guard let account = accounts.first(where: { $0.id == id }), !removing.contains(id) else { return }
        webFolders[id] = state.folder
        if account.usesWeb, let count = state.unread {
            unread[id] = count; badgeCheckedAt[id] = Date(); badgeErrors[id] = nil; updateDock()
        }
    }
    var scheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }

    init(persistence: AccountPersistence = AccountPersistence(), updateLookup: @escaping (String) async throws -> AppUpdateOffer? = { try await AppUpdateChecker.latest(currentVersion: $0) }) {
        self.persistence = persistence
        self.updateLookup = updateLookup
        do { accounts = try persistence.load() } catch { alert = "Impossible de lire les comptes sauvegardés. Le fichier est conservé : \(error.localizedDescription)" }
        selectedID = visibleAccounts.first?.id
        webSessions.mailboxDidChange = { [weak self] id, state in self?.syncMailbox(id, state) }
        webSessions.mailtoRequested = { [weak self] url in
            if let request = MailComposeRequest(mailto: url) { self?.receiveCompose(request) }
        }
        load()
    }
    func start() {
        if !checkedUpdatesAtStartup {
            checkedUpdatesAtStartup = true
            Task { [weak self] in await self?.checkForUpdates(prompt: true) }
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let started = Date()
                await self?.pollBadges()
                let delay = max(1, 60 - Date().timeIntervalSince(started))
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
            }
        }
    }
    func checkForUpdates(prompt: Bool = false) async {
        guard updateState != .checking else { return }
        updateState = .checking
        do {
            if let offer = try await updateLookup(programVersion) {
                updateState = .available(offer)
                if prompt { updatePrompt = offer }
            } else { updateState = .upToDate }
        } catch { updateState = .unavailable }
    }
    func openProgramVersion() {
        if case .available(let offer) = updateState {
            updatePrompt = offer
        } else { Task { await checkForUpdates(prompt: true) } }
    }
    func acceptUpdate(_ offer: AppUpdateOffer) {
        updatePrompt = nil
        guard updateState.offer == offer, !automaticUpdater.phase.busy else { return }
        guard !connecting, composeRequest == nil, !accountTransferInProgress, removing.isEmpty, AttachmentDownloads.shared.activeCount == 0 else {
            alert = "Terminez la connexion, la préparation du message, le téléchargement ou le transfert de comptes avant de lancer la mise à jour."
            return
        }
        automaticUpdater.install(offer)
    }
    func restoreBackup(_ backup: AccountBackup) async throws -> Int {
        try backup.validate()
        let candidates = backup.newProfiles(existing: accounts)
        let restored = try await AccountBackupTransfer.restore(candidates) { imported in
            let current = self.accounts
            let existingEmails = Set(current.map { $0.email.lowercased() })
            let accepted = imported.filter { !existingEmails.contains($0.email.lowercased()) }
            do { try self.persistence.save(current + accepted) }
            catch { try? self.persistence.save(current); throw error }
            self.accounts = current + accepted
            return accepted
        }
        if selectedID == nil { selectedID = restored.first?.id; load() }
        return restored.count
    }
    func select(_ account: MailAccount) {
        guard selectedID != account.id, !removing.contains(account.id) else { return }
        selectedID = account.id; search = ""; load()
    }
    func cycle(_ delta: Int) {
        guard let index = visibleAccounts.firstIndex(where: { $0.id == selectedID }), !visibleAccounts.isEmpty else { return }
        select(visibleAccounts[(index + delta + visibleAccounts.count) % visibleAccounts.count])
    }
    func load(more: Bool = false) {
        loadTask?.cancel(); bodyTask?.cancel(); bodyGeneration = UUID(); loadingBody = false
        generation = UUID()
        let stamp = generation
        guard let account = selectedAccount else { messages = []; selectedMessageID = nil; loading = false; return }
        if !more { messages = []; selectedMessageID = nil; nextPage = nil; hydrated.removeAll() }
        if account.usesWeb { loading = false; return }
        loading = true
        let query = folder.query + (search.isEmpty ? "" : " " + search)
        let cursor = more ? nextPage : nil
        loadTask = Task {
            do {
                let page = try await api.page(account: account.id, query: query, cursor: cursor)
                guard !Task.isCancelled, generation == stamp, !removing.contains(account.id) else { return }
                let known = Set(messages.map(\.id))
                messages.append(contentsOf: page.messages.filter { !known.contains($0.id) })
                nextPage = page.cursor; errors[account.id] = nil; loading = false
                if selectedMessageID == nil { selectedMessageID = messages.first?.id; loadBody() }
            } catch {
                guard !Task.isCancelled, generation == stamp else { return }
                errors[account.id] = error.localizedDescription; loading = false
            }
        }
    }
    func loadBody() {
        bodyTask?.cancel(); bodyGeneration = UUID(); loadingBody = false
        let stamp = bodyGeneration
        guard let message = selectedMessage, selectedAccount?.isDemo == false, !hydrated.contains(message.id) else { return }
        loadingBody = true
        bodyTask = Task {
            do {
                let full = try await api.message(id: message.id, account: message.accountID)
                guard !Task.isCancelled, bodyGeneration == stamp, selectedID == message.accountID, let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
                messages[index] = full; hydrated.insert(full.id); loadingBody = false
            } catch {
                guard !Task.isCancelled, bodyGeneration == stamp else { return }
                loadingBody = false; alert = error.localizedDescription
            }
        }
    }
    func addWebAccount(email rawEmail: String, name: String, group: String) {
        guard let email = AccountInput.email(rawEmail) else { alert = "Saisissez une adresse e-mail valide."; return }
        if let existing = accounts.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            selectedID = existing.id; webMode = true; showAdd = false; load(); return
        }
        var account = MailAccount(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? email.components(separatedBy: "@")[0] : name.trimmingCharacters(in: .whitespacesAndNewlines), email: email, group: group, colorIndex: accounts.count)
        account.webOnly = true
        do {
            let updated = accounts + [account]
            try persistence.save(updated); accounts = updated
            selectedID = account.id; webMode = true; showAdd = false
            search = ""; accountSearch = ""; load()
        } catch { alert = error.localizedDescription }
    }
    func connect(secret: String) async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        var provisional: UUID?
        do {
            let credential = try await auth.authorize(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
            let temporary = UUID(); provisional = temporary
            try KeychainStore.save(credential, for: temporary)
            let profile = try await api.profile(account: temporary)
            guard !auth.cancelled else { throw AerisError.message("Connexion annulée.") }
            let existing = accounts.first { $0.email.caseInsensitiveCompare(profile.emailAddress) == .orderedSame }
            var account = existing ?? MailAccount(id: temporary, name: profile.emailAddress.components(separatedBy: "@")[0], email: profile.emailAddress, group: "Travail", colorIndex: accounts.count)
            account.webOnly = false
            if existing != nil { try KeychainStore.save(credential, for: account.id); try KeychainStore.delete(temporary) }
            var updated = accounts
            if let index = updated.firstIndex(where: { $0.id == account.id }) { updated[index] = account } else { updated.append(account) }
            try persistence.save(updated); accounts = updated; provisional = nil
            selectedID = account.id; showAdd = false; webMode = false; search = ""; accountSearch = ""; load()
            await pollBadges()
        } catch {
            if let provisional { try? KeychainStore.delete(provisional) }
            alert = error.localizedDescription
        }
    }
    @discardableResult func update(_ account: MailAccount) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return false }
        var updated = accounts; updated[index] = account
        do { try persistence.save(updated); accounts = updated; return true }
        catch { alert = error.localizedDescription; return false }
    }
    func moveAccount(_ id: UUID, relativeTo targetID: UUID, after: Bool) {
        guard !removing.contains(id), !removing.contains(targetID) else { return }
        let updated = AccountOrdering.moving(id, relativeTo: targetID, after: after, in: visibleAccounts)
        guard updated != visibleAccounts else { return }
        do { try persistence.save(updated); accounts = updated }
        catch { alert = "Impossible de sauvegarder l’ordre des comptes : \(error.localizedDescription)" }
    }
    func rename(_ account: MailAccount, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !removing.contains(account.id) else { return false }
        guard var latest = accounts.first(where: { $0.id == account.id }) else { return false }
        latest.name = name
        return update(latest)
    }
    func remove(_ account: MailAccount) async {
        guard !removing.contains(account.id) else { return }
        removing.insert(account.id)
        defer { removing.remove(account.id) }
        if selectedID == account.id {
            loadTask?.cancel(); bodyTask?.cancel(); webMode = false; selectedID = nil
        }
        do {
            if !account.usesWeb {
                await api.prepareRemoval(account: account.id)
                try await api.revoke(account: account.id)
            }
            // Allow SwiftUI to detach a visible web view before deleting its store.
            await Task.yield()
            try await webSessions.remove(account.id)
            if !account.usesWeb { try KeychainStore.delete(account.id) }
            let updated = accounts.filter { $0.id != account.id }
            try persistence.save(updated); accounts = updated
            unread[account.id] = nil; errors[account.id] = nil; webFolders[account.id] = nil
            badgeErrors[account.id] = nil; badgeCheckedAt[account.id] = nil
            if selectedID == nil || selectedID == account.id { selectedID = visibleAccounts.first?.id; load() }
            updateDock()
        } catch { alert = "Le compte reste dans la liste pour permettre une nouvelle tentative. " + error.localizedDescription }
    }
    func pollBadges() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        let stamp = badgeGeneration
        var pending = accounts.filter { !removing.contains($0.id) }.makeIterator()
        // At most two temporary Gmail views, independent of the three-view UI cache.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                if let account = pending.next() { group.addTask { @MainActor in await self.checkBadge(account, stamp: stamp) } }
            }
            for await _ in group {
                if let account = pending.next() { group.addTask { @MainActor in await self.checkBadge(account, stamp: stamp) } }
            }
        }
        updateDock()
    }
    private func checkBadge(_ account: MailAccount, stamp: UUID) async {
        guard badgeGeneration == stamp, !Task.isCancelled, accounts.contains(where: { $0.id == account.id }), !removing.contains(account.id) else { return }
        checkingBadges.insert(account.id)
        defer { checkingBadges.remove(account.id) }
        let started = Date()
        do {
            let count = try await (account.usesWeb ? webSessions.checkUnread(account: account) : api.unread(account: account.id))
            guard badgeGeneration == stamp, accounts.contains(where: { $0.id == account.id }), !removing.contains(account.id) else { return }
            // A live Gmail update received during the probe is more recent.
            guard badgeCheckedAt[account.id].map({ $0 <= started }) ?? true else { return }
            let previous = unread[account.id]
            unread[account.id] = count; badgeCheckedAt[account.id] = Date(); badgeErrors[account.id] = nil
            if !account.usesWeb {
                errors[account.id] = nil
                if let previous, count > previous, account.notifications { notify(account: account, count: count - previous) }
            }
        } catch is CancellationError { }
        catch {
            guard badgeGeneration == stamp, accounts.contains(where: { $0.id == account.id }), !removing.contains(account.id) else { return }
            if badgeCheckedAt[account.id].map({ $0 <= started }) ?? true { badgeErrors[account.id] = error.localizedDescription }
        }
    }
    func badgeHelp(_ account: MailAccount) -> String {
        var text = unread[account.id].map { "\($0) message(s) non lu(s) dans la réception." } ?? "Nombre de non lus en attente de vérification."
        if let date = badgeCheckedAt[account.id] { text += " Relevé à \(date.formatted(date: .omitted, time: .standard))." }
        if let issue = badgeErrors[account.id] { text += " Dernier relevé échoué : \(issue)" }
        if checkingBadges.contains(account.id) { text += " Vérification en cours." }
        return text + " Glissez pour déplacer ce compte."
    }
    func refresh() {
        if let account = selectedAccount, !account.isDemo, account.usesWeb || webMode { webSessions.reload(account: account) }
        else { load() }
        Task { await pollBadges() }
    }
    func updateDock() {
        let count = accounts.reduce(0) { $0 + (unread[$1.id] ?? 0) }
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }
    func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            notificationStatus = granted ? "Activées" : "Refusées dans macOS"
        } catch { notificationStatus = "Indisponibles"; alert = error.localizedDescription }
    }
    private func notify(account: MailAccount, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Inboxy · \(account.name)"; content.body = "\(count) message(s) non lu(s) supplémentaire(s)."
        content.sound = .default; content.userInfo = ["accountID": account.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in }
    }
    private var composeQueue: [MailComposeRequest] = []
    func receiveCompose(_ request: MailComposeRequest) {
        if composeRequest != nil { composeQueue.append(request) }
        else { composeRequest = request }
    }
    func advanceComposeQueue() {
        if composeRequest == nil, !composeQueue.isEmpty { composeRequest = composeQueue.removeFirst() }
    }
    func compose(_ request: MailComposeRequest, from account: MailAccount) {
        guard accounts.contains(where: { $0.id == account.id }), !removing.contains(account.id) else { return }
        do {
            var validated = request
            validated.files = try MailComposeRequest.readableFiles(request.files)
            select(account); webMode = true
            webSessions.compose(account: account, request: validated)
            composeRequest = nil
        } catch { alert = error.localizedDescription }
    }
    func openGmail(compose: Bool = false) {
        guard let account = selectedAccount else { showAdd = true; return }
        if account.usesWeb {
            webMode = true
            let url = URL(string: "https://mail.google.com/mail/u/0/#" + (compose ? "inbox?compose=new" : "inbox"))!
            webSessions.view(for: account).load(URLRequest(url: url))
            return
        }
        var url = URLComponents(string: "https://mail.google.com/mail/u/")!
        url.queryItems = [URLQueryItem(name: "authuser", value: account.email)]
        url.fragment = compose ? "inbox?compose=new" : selectedMessageID.map { "inbox/\($0)" } ?? "inbox"
        NSWorkspace.shared.open(url.url!)
    }
}
