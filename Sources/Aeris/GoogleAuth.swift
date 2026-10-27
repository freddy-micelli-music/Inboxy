import Foundation
import AppKit
import CryptoKit
import Security
import Network

struct GoogleToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var clientID: String
    var clientSecret: String
}

enum KeychainStore {
    static let service = "fr.aeris.mail.oauth"
    static func save(_ token: GoogleToken, for id: UUID) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw AerisError.message("Écriture au Trousseau impossible (\(status)).") }
        } else if update != errSecSuccess { throw AerisError.message("Mise à jour du Trousseau impossible (\(update)).") }
    }
    static func read(_ id: UUID) throws -> GoogleToken {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw AerisError.message("Session absente ou Trousseau verrouillé. Reconnectez ce compte (\(status)).") }
        return try JSONDecoder().decode(GoogleToken.self, from: data)
    }
    static func delete(_ id: UUID) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AerisError.message("Suppression du Trousseau impossible (\(status)).") }
    }
}

enum OAuthTools {
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AerisError.message("Génération aléatoire impossible.") }
        return Data(bytes).base64URL
    }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    static func callback(_ target: String, state: String) throws -> String {
        guard let parts = URLComponents(string: "http://127.0.0.1" + target), parts.path == "/oauth/callback" else { throw AerisError.message("Adresse de retour invalide.") }
        let fields = parts.queryItems ?? []
        guard fields.filter({ $0.name == "state" }).count == 1, fields.first(where: { $0.name == "state" })?.value == state else { throw AerisError.message("Vérification de la connexion échouée.") }
        if fields.contains(where: { $0.name == "error" }) { throw AerisError.message("Connexion refusée ou annulée dans Google.") }
        guard let code = fields.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AerisError.message("Google n’a pas renvoyé de code.") }
        return code
    }
}

struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Double
    let refresh_token: String?
}

@MainActor final class GoogleAuth {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var redirect = ""
    private(set) var cancelled = false
    private let network = URLSession(configuration: .ephemeral)

    func cancel() { cancelled = true; finish(.failure(AerisError.message("Connexion annulée."))) }
    private func finish(_ result: Result<String, Error>) {
        let pending = continuation
        continuation = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        pending?.resume(with: result)
    }
    func authorize(clientID: String, secret: String) async throws -> GoogleToken {
        guard continuation == nil else { throw AerisError.message("Une connexion est déjà en cours.") }
        cancelled = false
        let verifier = try OAuthTools.random(), state = try OAuthTools.random()
        let parameters = NWParameters.tcp
        // The listener must never bind to Wi-Fi/Ethernet interfaces.
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        let code: String = try await withCheckedThrowingContinuation { pending in
            continuation = pending
            server.stateUpdateHandler = { [weak self] status in
                MainActor.assumeIsolated {
                guard let self, self.continuation != nil else { return }
                switch status {
                case .ready:
                    guard let port = server.port else { self.finish(.failure(AerisError.message("Port local indisponible."))); return }
                    self.redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
                    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                    url.queryItems = ["client_id": clientID, "redirect_uri": self.redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/gmail.readonly", "state": state, "code_challenge": OAuthTools.challenge(verifier), "code_challenge_method": "S256", "access_type": "offline", "prompt": "consent select_account"].map { URLQueryItem(name: $0.key, value: $0.value) }
                    if !NSWorkspace.shared.open(url.url!) { self.finish(.failure(AerisError.message("Impossible d’ouvrir le navigateur."))) }
                case .failed: self.finish(.failure(AerisError.message("Impossible de recevoir la réponse Google sur ce Mac.")))
                default: break
                }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                connection.start(queue: .main)
                self?.receive(connection, buffer: Data(), expectedState: state)
                }
            }
            server.start(queue: .main)
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(AerisError.message("Délai de connexion dépassé. Réessayez.")))
            }
        }
        var fields = ["client_id": clientID, "code": code, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect]
        if !secret.isEmpty { fields["client_secret"] = secret }
        let response = try await exchange(fields)
        guard !cancelled else { throw AerisError.message("Connexion annulée.") }
        guard let refresh = response.refresh_token else { throw AerisError.message("Google n’a pas fourni de session durable. Réessayez en autorisant l’accès hors ligne.") }
        return GoogleToken(accessToken: response.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(response.expires_in), clientID: clientID, clientSecret: secret)
    }
    private func receive(_ connection: NWConnection, buffer: Data, expectedState: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
            guard let self else { connection.cancel(); return }
            var bytes = buffer; bytes.append(data ?? Data())
            guard bytes.count <= 16384, error == nil else { connection.cancel(); return }
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, buffer: bytes, expectedState: expectedState) }; return
            }
            let line = request.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/oauth/callback?") else { connection.cancel(); return }
            let result = Result { try OAuthTools.callback(String(line[1]), state: expectedState) }
            let text: String
            switch result { case .success: text = "Connexion reçue. Vous pouvez revenir dans Inboxy."; case .failure: text = "Connexion non validée. Revenez dans Inboxy pour réessayer." }
            let body = "<!doctype html><meta charset='utf-8'><title>Inboxy</title><body style='background:#111c1b;color:#e8f3ee;font:22px -apple-system;padding:80px'><h1>Inboxy ✦</h1><p>\(text)</p></body>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            // Invalid state requests cannot terminate the pending legitimate flow.
            if URLComponents(string: "http://localhost" + String(line[1]))?.queryItems?.first(where: { $0.name == "state" })?.value == expectedState {
                self.finish(result)
            }
            }
        }
    }
    func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.httpBody = formData(fields); request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await network.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AerisError.message("Google a refusé la session. Vérifiez le client OAuth de type Application de bureau, les utilisateurs de test et les autorisations ; reconnectez le compte si nécessaire.") }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
