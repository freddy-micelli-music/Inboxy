import Foundation
import SwiftUI

// Explicit alias retains the macOS 14 property wrapper with newer SwiftUI SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>

struct MailAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var group: String
    var colorIndex: Int = 0
    var isDemo: Bool = false
    var notifications: Bool = true
    // Optional for decoding accounts created before integrated Gmail profiles.
    var webOnly: Bool? = nil
    var usesWeb: Bool { webOnly == true }
    var initials: String { String(name.split(separator: " ").prefix(2).compactMap(\.first)) }
    var color: Color { Palette.colors[abs(colorIndex % Palette.colors.count)] }
}

enum AccountOrdering {
    static func moving(_ id: UUID, relativeTo targetID: UUID, after: Bool, in accounts: [MailAccount]) -> [MailAccount] {
        guard id != targetID, let source = accounts.first(where: { $0.id == id }),
              let target = accounts.first(where: { $0.id == targetID }) else { return accounts }
        var result = accounts.filter { $0.id != id }
        guard let targetIndex = result.firstIndex(where: { $0.id == targetID }) else { return accounts }
        var moved = source
        moved.group = target.group
        result.insert(moved, at: targetIndex + (after ? 1 : 0))
        return result
    }
}

enum AccountInput {
    static func email(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !value.contains(where: { $0.isWhitespace || $0.isNewline }), value.count <= 254 else { return nil }
        return value
    }
}

enum Palette {
    static let navigationBackground = Color(red: 0.055, green: 0.095, blue: 0.09)
    static let accent = Color(red: 0.18, green: 0.64, blue: 0.53)
    static let colors: [Color] = [accent, .init(red: 0.48, green: 0.48, blue: 0.77), .init(red: 0.80, green: 0.55, blue: 0.35), .init(red: 0.35, green: 0.56, blue: 0.76), .init(red: 0.73, green: 0.44, blue: 0.53)]
}

struct MailMessage: Identifiable, Equatable {
    var id: String
    var accountID: UUID
    var sender: String
    var senderEmail: String
    var subject: String
    var snippet: String
    var body: String
    var date: Date
    var unread: Bool
    var starred: Bool
    var labels: [String]
}

enum MailFolder: String, CaseIterable, Identifiable {
    case inbox = "Boîte de réception", unread = "Non lus", starred = "Favoris", sent = "Envoyés", trash = "Corbeille"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .inbox: return "tray"; case .unread: return "circle.dotted"; case .starred: return "star"; case .sent: return "paperplane"; case .trash: return "trash" }
    }
    var query: String {
        switch self { case .inbox: return "in:inbox"; case .unread: return "in:inbox is:unread"; case .starred: return "is:starred"; case .sent: return "in:sent"; case .trash: return "in:trash" }
    }
}

enum DemoData {
    static let names = ["Studio principal", "Personnel", "Atelier créatif", "Équipe produit", "Relations clients", "Administration", "Comptabilité", "Voyages", "Presse & médias", "Partenariats", "Architecture", "Photographie", "Éditions", "Direction", "Production", "Support", "Événements", "Design", "Développement", "Recherche", "Marketing", "Juridique", "Recrutement", "Communauté", "Formation", "International", "Boutique", "Archives", "Projets spéciaux", "Investissements", "Immobilier", "Association", "Musique", "Famille", "Veille", "Laboratoire"]
    static func accounts() -> [MailAccount] {
        names.enumerated().map { i, name in
            MailAccount(name: name, email: "\(i == 0 ? "bonjour" : "compte\(i + 1)")@exemple.test", group: i == 1 || i >= 32 ? "Personnel" : "Travail", colorIndex: i, isDemo: true)
        }
    }
    static func messages(for account: MailAccount) -> [MailMessage] {
        let rows: [(String, String, String, String)] = [
            ("Camille Laurent", "La suite commence ici", "J’ai pris le temps de réunir nos idées pour la prochaine étape. Le résultat me plaît beaucoup.", "Bonjour,\n\nJ’ai pris le temps de réunir nos idées pour la prochaine étape. Le résultat me plaît beaucoup.\n\nUne direction plus simple, des matières naturelles et une vraie attention portée aux détails : c’est exactement ce que nous avions imaginé ensemble.\n\nJe vous propose que l’on se retrouve mardi à 10 h pour parcourir les dernières pistes. D’ici là, vos remarques sont les bienvenues.\n\nÀ très vite,\nCamille\n\nDirection de création · Atelier Horizon"),
            ("Maison Kitsuné", "Une invitation, rien que pour vous", "Notre nouvelle collection se découvre en avant-première jeudi soir.", "Bonjour,\n\nNous serions heureux de vous accueillir pour découvrir notre nouvelle collection.\n\nRendez-vous jeudi à partir de 18 h dans notre espace parisien.\n\nL’équipe Maison Kitsuné"),
            ("Thomas Bernard", "Projet Horizon — les dernières pistes", "Les trois propositions sont prêtes. On en parle demain ?", "Bonjour,\n\nLes trois propositions sont prêtes. J’ai intégré les retours de toute l’équipe.\n\nOn en parle demain ?\n\nThomas"),
            ("Notion", "Votre semaine, en perspective", "Retrouvez les nouvelles de votre espace de travail.", "Voici les dernières nouvelles de votre espace de travail.\n\nTrois projets ont avancé cette semaine. Prenez un moment pour les découvrir."),
            ("Léa Moreau", "Un café la semaine prochaine ?", "Je passe dans le quartier et j’aimerais vous retrouver.", "Bonjour !\n\nJe passe dans le quartier la semaine prochaine. Ce serait un plaisir de vous retrouver autour d’un café.\n\nÀ bientôt,\nLéa"),
            ("Linear", "Le point sur vos projets", "Une belle progression pour l’équipe cette semaine.", "Le point sur vos projets\n\nDouze tâches terminées, trois nouveaux jalons. Toute l’équipe avance dans la même direction."),
            ("Arthur Petit", "Quelques images de Lisbonne", "La lumière était incroyable. Voici une première sélection.", "Bonjour,\n\nLa lumière était incroyable à Lisbonne. J’ai préparé une première sélection pour notre prochain échange.\n\nArthur"),
            ("Équipe Inboxy", "Un espace pour chaque univers", "Vos comptes, réunis avec élégance. Bienvenue dans la démonstration.", "Bienvenue dans Inboxy.\n\nCes messages sont fictifs. Vous pouvez explorer 36 comptes, filtrer les messages, changer de thème et essayer le sélecteur rapide.\n\nPour vos vrais messages, ajoutez un compte Google depuis le bouton +. La connexion s’effectue dans votre navigateur.\n\nBonne découverte.")
        ]
        return rows.enumerated().map { i, row in
            MailMessage(id: "demo-\(account.id)-\(i)", accountID: account.id, sender: row.0, senderEmail: "contact@exemple.test", subject: row.1, snippet: row.2, body: row.3, date: Date().addingTimeInterval(-Double(i * 3200 + 180)), unread: i < 3, starred: i == 0 || i == 4, labels: [i == 7 ? "SENT" : "INBOX"])
        }
    }
}

struct AccountPersistence {
    let url: URL
    init(root: URL? = nil) {
        let directory = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aeris", isDirectory: true)
        url = directory.appendingPathComponent("accounts.json")
    }
    func load() throws -> [MailAccount] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([MailAccount].self, from: Data(contentsOf: url))
    }
    func save(_ accounts: [MailAccount]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(accounts.filter { !$0.isDemo }).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4))
    }
}

func formData(_ fields: [String: String]) -> Data {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return fields.sorted { $0.key < $1.key }.map { key, value in
        "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&").data(using: .utf8)!
}

enum AerisError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}


enum NavigationPlacement: String, CaseIterable, Identifiable {
    case left, top, bottom, right
    var id: String { rawValue }
    var horizontal: Bool { self == .top || self == .bottom }
    var beforeWorkspace: Bool { self == .left || self == .top }
    var label: String {
        switch self { case .left: return "À gauche"; case .top: return "En haut"; case .bottom: return "En bas"; case .right: return "À droite" }
    }
    var symbol: String {
        switch self { case .left: return "sidebar.left"; case .right: return "sidebar.right"; case .top: return "rectangle.topthird.inset.filled"; case .bottom: return "rectangle.bottomthird.inset.filled" }
    }
}

struct MailComposeRequest: Identifiable {
    let id = UUID()
    var files: [URL] = []
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    init(files: [URL] = []) { self.files = files }
    init?(mailto: URL) {
        guard mailto.scheme?.lowercased() == "mailto", let parts = URLComponents(url: mailto, resolvingAgainstBaseURL: false) else { return nil }
        to = parts.path
        for item in parts.queryItems ?? [] {
            switch item.name.lowercased() {
            case "to": to = [to, item.value ?? ""].filter { !$0.isEmpty }.joined(separator: ",")
            case "cc": cc = item.value ?? ""
            case "bcc": bcc = item.value ?? ""
            case "subject": subject = item.value ?? ""
            case "body": body = item.value ?? ""
            default: break
            }
        }
    }
    init(seeviewDocument url: URL) throws {
        struct Envelope: Decodable { var version: Int; var to: String; var subject: String; var body: String; var attachment: String }
        guard url.isFileURL, url.pathExtension.lowercased() == "seeviewmail",
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64_000 else { throw AerisError.message("Le brouillon Seeview-Pro est invalide ou trop volumineux.") }
        let data = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard data.version == 1, !data.attachment.isEmpty, data.attachment == (data.attachment as NSString).lastPathComponent,
              !data.attachment.contains(".."), (data.attachment as NSString).pathExtension.lowercased() == "pdf" else { throw AerisError.message("Pièce jointe du brouillon invalide.") }
        let root = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let attachment = root.appendingPathComponent(data.attachment).resolvingSymlinksInPath().standardizedFileURL
        guard attachment.deletingLastPathComponent() == root else { throw AerisError.message("La pièce jointe doit accompagner le brouillon dans le même dossier.") }
        let checked = try Self.readableFiles([attachment])
        let file = try FileHandle(forReadingFrom: attachment); defer { try? file.close() }
        guard try file.read(upToCount: 5) == Data("%PDF-".utf8) else { throw AerisError.message("La pièce jointe n’est pas un PDF lisible.") }
        self.files = checked; self.to = data.to; self.subject = data.subject; self.body = data.body
    }
    func gmailURL(account: MailAccount) -> URL {
        var parts = URLComponents(string: "https://mail.google.com/mail/u/0/")!
        parts.queryItems = [URLQueryItem(name: "authuser", value: account.email), URLQueryItem(name: "view", value: "cm"), URLQueryItem(name: "fs", value: "1")]
        for (key, value) in [("to", to), ("cc", cc), ("bcc", bcc), ("su", subject), ("body", body)] where !value.isEmpty {
            parts.queryItems?.append(URLQueryItem(name: key, value: value))
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
    static func readableFiles(_ urls: [URL]) throws -> [URL] {
        var seen = Set<URL>()
        return try urls.map { $0.standardizedFileURL }.filter { seen.insert($0).inserted }.map { url in
            guard url.isFileURL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                throw AerisError.message("Le fichier « \(url.lastPathComponent) » est inaccessible ou est un dossier. Pour envoyer un dossier, compressez-le d’abord dans le Finder.")
            }
            return url
        }
    }
}

// Stable numeric versions only: a beta tag never becomes an update for a stable build.
struct ProgramVersion: Comparable {
    let components: [Int]
    let text: String
    init?(_ tag: String) {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 9 && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0")
        }) else { return nil }
        components = parts.compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        text = value
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.components == rhs.components }
}

struct AppUpdateOffer: Equatable {
    let version: String
    let releaseURL: URL
}

enum AppUpdateState: Equatable {
    case idle, checking, upToDate, unavailable, available(AppUpdateOffer)
    var offer: AppUpdateOffer? { if case .available(let value) = self { return value }; return nil }
    func label(version: String) -> String {
        switch self {
        case .idle: return "Version \(version)"
        case .checking: return "Version \(version) · Vérification…"
        case .upToDate: return "Version \(version) · À jour"
        case .unavailable: return "Version \(version) · À vérifier"
        case .available(let offer): return "v\(version) · \(offer.version) disponible"
        }
    }
}

enum AppUpdateChecker {
    static let endpoint = URL(string: "https://api.github.com/repos/freddy-micelli-music/Inboxy/releases/latest")!
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    static func offer(from data: Data, currentVersion: String) throws -> AppUpdateOffer? {
        guard data.count <= 512_000, let current = ProgramVersion(currentVersion) else {
            throw AerisError.message("Version ou réponse de mise à jour invalide.")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, let latest = ProgramVersion(release.tag_name) else {
            throw AerisError.message("La publication n’est pas une version stable.")
        }
        guard latest > current else { return nil }
        let pagePath = "/freddy-micelli-music/Inboxy/releases/tag/\(release.tag_name)"
        let fileName = "Inboxy-\(latest.text)-macOS.zip"
        let downloadPath = "/freddy-micelli-music/Inboxy/releases/download/\(release.tag_name)/\(fileName)"
        guard trustedURL(release.html_url, path: pagePath), release.assets.contains(where: {
            $0.name == fileName && $0.state == "uploaded" && $0.size > 0 && trustedURL($0.browser_download_url, path: downloadPath)
        }) else { throw AerisError.message("Le téléchargement Inboxy n’est pas encore disponible.") }
        return AppUpdateOffer(version: latest.text, releaseURL: release.html_url)
    }
    private static func trustedURL(_ url: URL, path: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path == path
            && url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
    }
    static func latest(currentVersion: String, session suppliedSession: URLSession? = nil) async throws -> AppUpdateOffer? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = suppliedSession ?? URLSession(configuration: configuration)
        defer { if suppliedSession == nil { session.finishTasksAndInvalidate() } }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Inboxy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == endpoint else {
            throw AerisError.message("Vérification GitHub indisponible.")
        }
        return try offer(from: data, currentVersion: currentVersion)
    }
}
