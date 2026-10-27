import Foundation

struct GmailProfile: Decodable { let emailAddress: String }
struct GmailLabel: Decodable { let messagesUnread: Int? }
struct GmailPage: Decodable {
    struct Reference: Decodable { let id: String }
    let messages: [Reference]?
    let nextPageToken: String?
}
struct GmailPayload: Decodable {
    struct Header: Decodable { let name: String; let value: String }
    struct Body: Decodable { let data: String?; let attachmentId: String? }
    let mimeType: String?
    let headers: [Header]?
    let body: Body?
    let parts: [GmailPayload]?
    func header(_ name: String) -> String { headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? "" }
    var plainText: String? {
        if mimeType == "text/plain", let encoded = body?.data, let data = Data(base64URL: encoded) {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        return parts?.compactMap(\.plainText).first
    }
}
struct GmailMessage: Decodable {
    let id: String
    let snippet: String?
    let internalDate: String?
    let labelIds: [String]?
    let payload: GmailPayload?
    func mail(accountID: UUID) -> MailMessage {
        let from = payload?.header("From") ?? ""
        let name = from.components(separatedBy: "<")[0].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let address = from.contains("<") ? from.components(separatedBy: "<").last!.replacingOccurrences(of: ">", with: "") : from
        return MailMessage(id: id, accountID: accountID, sender: name.isEmpty ? address : name, senderEmail: address, subject: payload?.header("Subject").nilIfEmpty ?? "Sans objet", snippet: snippet ?? "", body: payload?.plainText ?? "Ce message ne contient pas de version texte intégrée. Ouvrez-le dans Gmail pour afficher le HTML et les pièces jointes.\n\n" + (snippet ?? ""), date: Date(timeIntervalSince1970: (Double(internalDate ?? "0") ?? 0) / 1000), unread: labelIds?.contains("UNREAD") ?? false, starred: labelIds?.contains("STARRED") ?? false, labels: labelIds ?? [])
    }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

@MainActor final class GmailAPI {
    private let auth = GoogleAuth()
    private let network: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    private var refreshes: [UUID: Task<GoogleToken, Error>] = [:]
    func token(_ id: UUID, force: Bool = false) async throws -> GoogleToken {
        if let pending = refreshes[id] { return try await pending.value }
        let old = try KeychainStore.read(id)
        if !force && old.expiresAt > Date().addingTimeInterval(60) { return old }
        let task = Task { () throws -> GoogleToken in
            var fields = ["client_id": old.clientID, "refresh_token": old.refreshToken, "grant_type": "refresh_token"]
            if !old.clientSecret.isEmpty { fields["client_secret"] = old.clientSecret }
            let response = try await auth.exchange(fields)
            try Task.checkCancellation()
            var updated = old
            updated.accessToken = response.access_token
            updated.refreshToken = response.refresh_token ?? old.refreshToken
            updated.expiresAt = Date().addingTimeInterval(response.expires_in)
            try KeychainStore.save(updated, for: id)
            return updated
        }
        refreshes[id] = task
        defer { refreshes[id] = nil }
        return try await task.value
    }
    func get<T: Decodable>(_ path: String, account: UUID, query: [String: String] = [:], retry: Bool = true) async throws -> T {
        let credential = try await token(account)
        var parts = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && retry {
            _ = try await token(account, force: true)
            return try await get(path, account: account, query: query, retry: false)
        }
        guard (200..<300).contains(status) else {
            throw AerisError.message(status == 429 ? "Limite Gmail atteinte. La synchronisation réessaiera au prochain cycle." : "Gmail a refusé la demande (\(status)). Vérifiez l’activation de l’API et l’accès au compte.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func profile(account: UUID) async throws -> GmailProfile { try await get("profile", account: account) }
    func unread(account: UUID) async throws -> Int {
        let label: GmailLabel = try await get("labels/INBOX", account: account)
        return label.messagesUnread ?? 0
    }
    func page(account: UUID, query: String, cursor: String? = nil) async throws -> (messages: [MailMessage], cursor: String?) {
        var fields = ["q": query, "maxResults": "25"]
        if let cursor { fields["pageToken"] = cursor }
        let page: GmailPage = try await get("messages", account: account, query: fields)
        // Bounded sequential fetching avoids a burst of requests across 30+ accounts.
        var messages: [MailMessage] = []
        for ref in page.messages ?? [] {
            try Task.checkCancellation()
            let raw: GmailMessage = try await get("messages/" + ref.id, account: account, query: ["format": "metadata"])
            messages.append(raw.mail(accountID: account))
        }
        return (messages, page.nextPageToken)
    }
    func message(id: String, account: UUID) async throws -> MailMessage {
        let raw: GmailMessage = try await get("messages/" + id, account: account, query: ["format": "full"])
        return raw.mail(accountID: account)
    }
    func prepareRemoval(account: UUID) async {
        if let task = refreshes[account] { task.cancel(); _ = try? await task.value; refreshes[account] = nil }
    }
    func revoke(account: UUID) async throws {
        let credential = try KeychainStore.read(account)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"; request.httpBody = formData(["token": credential.refreshToken])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await network.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 || (status == 400 && body?["error"] as? String == "invalid_token") else { throw AerisError.message("Révocation Google impossible. Réessayez lorsque la connexion est rétablie.") }
    }
}
