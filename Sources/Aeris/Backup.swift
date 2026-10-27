import Foundation
import WebKit
import CryptoKit
import CommonCrypto
import Security

struct BackupCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?
    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        expires = cookie.expiresDate; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
        sameSite = cookie.properties?[HTTPCookiePropertyKey(rawValue: "SameSite")] as? String
    }
    func cookie() throws -> HTTPCookie {
        guard !name.isEmpty, name.count <= 4096, value.utf8.count <= 100_000,
              ![name, value, domain, path].contains(where: { $0.utf8.contains(where: { $0 < 32 || $0 == 127 }) }),
              !domain.isEmpty, domain.count <= 255, path.hasPrefix("/"), path.count <= 2048 else { throw BackupArchive.invalid }
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        if let sameSite { properties[HTTPCookiePropertyKey(rawValue: "SameSite")] = sameSite }
        guard let result = HTTPCookie(properties: properties) else { throw BackupArchive.invalid }
        return result
    }
}
struct BackupProfile: Codable {
    var account: MailAccount
    var cookies: [BackupCookie]
    var localStorage: Data?
    var credential: GoogleToken?
}
struct AccountBackup: Codable {
    var format = "InboxyAccountBackup"
    var version = 1
    var createdAt = Date()
    var profiles: [BackupProfile]
    func validate() throws {
        guard format == "InboxyAccountBackup", version == 1, !profiles.isEmpty, profiles.count <= 500,
              Set(profiles.map { $0.account.id }).count == profiles.count,
              Set(profiles.map { $0.account.email.lowercased() }).count == profiles.count else { throw BackupArchive.invalid }
        for profile in profiles {
            let account = profile.account
            guard !account.isDemo, AccountInput.email(account.email) == account.email,
                  account.name.count <= 300, ["Travail", "Personnel"].contains(account.group),
                  profile.cookies.count <= 10_000, (profile.localStorage?.count ?? 0) <= 32_000_000 else { throw BackupArchive.invalid }
            for item in profile.cookies { _ = try item.cookie() }
            if let token = profile.credential {
                guard !token.clientID.isEmpty, token.clientID.count < 4096, token.refreshToken.count < 100_000,
                      token.accessToken.count < 100_000, token.clientSecret.count < 100_000 else { throw BackupArchive.invalid }
            }
        }
    }
    func newProfiles(existing: [MailAccount]) -> [BackupProfile] {
        let emails = Set(existing.map { $0.email.lowercased() })
        return profiles.filter { !emails.contains($0.account.email.lowercased()) }
    }
}
enum BackupArchive {
    static let invalid = AerisError.message("Ce fichier n’est pas une sauvegarde Inboxy valide ou compatible.")
    static let maximumSize = 64_000_000
    private struct Envelope: Codable {
        var format = "InboxyEncryptedBackup"
        var version = 1
        var rounds = 200_000
        var salt: Data
        var sealed: Data
    }
    private static func key(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let result = passwordBytes.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: Int8.self).baseAddress,
                    passwordBytes.count, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &derived, 32)
            }
        }
        guard result == kCCSuccess else { throw AerisError.message("Impossible de protéger la sauvegarde.") }
        return SymmetricKey(data: derived)
    }
    static func encrypt(_ backup: AccountBackup, password: String) throws -> Data {
        guard password.count >= 8 else { throw AerisError.message("Choisissez un mot de passe de sauvegarde d’au moins 8 caractères.") }
        try backup.validate()
        let plain = try JSONEncoder().encode(backup)
        guard plain.count < maximumSize / 2 else { throw AerisError.message("La sauvegarde est trop volumineuse.") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw invalid }
        let salt = Data(bytes)
        let sealed = try AES.GCM.seal(plain, using: key(password: password, salt: salt), authenticating: Data("Inboxy backup v1".utf8))
        guard let combined = sealed.combined else { throw invalid }
        return try JSONEncoder().encode(Envelope(salt: salt, sealed: combined))
    }
    static func decrypt(_ file: Data, password: String) throws -> AccountBackup {
        guard file.count <= maximumSize else { throw invalid }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: file) } catch { throw invalid }
        guard envelope.format == "InboxyEncryptedBackup", envelope.version == 1, envelope.rounds == 200_000,
              envelope.salt.count == 32, envelope.sealed.count >= 28 else { throw invalid }
        let plain: Data
        do {
            plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key(password: password, salt: envelope.salt), authenticating: Data("Inboxy backup v1".utf8))
        } catch { throw AerisError.message("Mot de passe incorrect ou sauvegarde endommagée.") }
        let backup: AccountBackup
        do { backup = try JSONDecoder().decode(AccountBackup.self, from: plain) } catch { throw invalid }
        try backup.validate()
        return backup
    }
}

@MainActor enum AccountBackupTransfer {
    static func capture(_ accounts: [MailAccount]) async throws -> AccountBackup {
        guard !accounts.isEmpty else { throw AerisError.message("Ajoutez un compte avant de créer une sauvegarde.") }
        var profiles: [BackupProfile] = []
        for account in accounts {
            let store = WKWebsiteDataStore(forIdentifier: account.id)
            let cookies = await store.httpCookieStore.allCookies().map(BackupCookie.init)
            var local: Data?
            if #available(macOS 26.0, *) {
                local = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    store.fetchData(of: [WKWebsiteDataTypeLocalStorage]) { data, error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data) }
                    }
                }
            }
            let credential = account.usesWeb ? nil : (try? KeychainStore.read(account.id))
            profiles.append(BackupProfile(account: account, cookies: cookies, localStorage: local, credential: credential))
        }
        let backup = AccountBackup(profiles: profiles)
        try backup.validate()
        return backup
    }
    // Every imported session gets a new store. Existing profiles are never overwritten.
    static func restore(_ profiles: [BackupProfile], persist: ([MailAccount]) throws -> [MailAccount]) async throws -> [MailAccount] {
        var imported: [MailAccount] = []
        var createdIDs: [UUID] = []
        do {
            for profile in profiles {
                var account = profile.account
                account.id = UUID()
                createdIDs.append(account.id)
                let store = WKWebsiteDataStore(forIdentifier: account.id)
                if #available(macOS 26.0, *), let local = profile.localStorage {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        store.restoreData(local) { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                }
                for item in profile.cookies {
                    let cookie = try item.cookie()
                    if cookie.expiresDate.map({ $0 > Date() }) ?? true { await store.httpCookieStore.setCookie(cookie) }
                }
                if let token = profile.credential, !account.usesWeb { try KeychainStore.save(token, for: account.id) }
                imported.append(account)
            }
            let accepted = try persist(imported)
            let acceptedIDs = Set(accepted.map(\.id))
            for id in createdIDs where !acceptedIDs.contains(id) {
                try? KeychainStore.delete(id)
                try? await WKWebsiteDataStore.remove(forIdentifier: id)
            }
            return accepted
        } catch {
            for id in createdIDs {
                try? KeychainStore.delete(id)
                try? await WKWebsiteDataStore.remove(forIdentifier: id)
            }
            throw error
        }
    }
}
