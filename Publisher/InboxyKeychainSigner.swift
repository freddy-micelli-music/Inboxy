import Foundation
import Security
import CryptoKit

// Publisher utility, run manually by the Mac owner. No private key is exported.
// Explicit Keychain references prevent falling back to the existing login Keychain.
enum SigningFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@main struct InboxyKeychainSigner {
    static let service = "fr.inboxy.signing.ed25519"
    static let account = "Inboxy"
    static let officialToolHash = "43c249771bafc3aa581228abae00731a012d324691b8292860896635050be76b"
    static let location = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/Inboxy-signing.keychain-db")

    static func require(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Erreur système"
            throw SigningFailure.message("Trousseau Inboxy : \(detail) (\(status)). Le trousseau session n’a pas été utilisé.")
        }
    }
    static func open(create: Bool) throws -> SecKeychain {
        var chain: SecKeychain?
        let result = SecKeychainOpen(location.path, &chain)
        if create && !FileManager.default.fileExists(atPath: location.path) {
            // SecKeychainCreate may add the new chain to the search list. Restore
            // the original list immediately; signing always uses the explicit ref.
            var originalList: CFArray?
            try require(SecKeychainCopySearchList(&originalList))
            var originalDefault: SecKeychain?
            try require(SecKeychainCopyDefault(&originalDefault))
            defer { if let originalList { _ = SecKeychainSetSearchList(originalList) } }
            print("Choisissez un NOUVEAU mot de passe pour le trousseau Inboxy dans la fenêtre macOS.")
            print("Il ne s’agit pas du mot de passe du trousseau session.")
            fflush(stdout)
            try require(SecKeychainCreate(location.path, 0, nil, true, nil, &chain))
            var settings = SecKeychainSettings(version: UInt32(SEC_KEYCHAIN_SETTINGS_VERS1), lockOnSleep: true, useLockInterval: true, lockInterval: 600)
            if let chain { try require(SecKeychainSetSettings(chain, &settings)) }
        } else { try require(result) }
        guard let chain else { throw SigningFailure.message("Le trousseau Inboxy n’a pas été ouvert.") }
        return chain
    }
    static func key(in chain: SecKeychain, create: Bool) throws -> Curve25519.Signing.PrivateKey {
        var length: UInt32 = 0
        var pointer: UnsafeMutableRawPointer?
        let status = SecKeychainFindGenericPassword(chain, UInt32(service.utf8.count), service, UInt32(account.utf8.count), account, &length, &pointer, nil)
        if status == errSecItemNotFound && create {
            let value = Curve25519.Signing.PrivateKey()
            var seed = value.rawRepresentation
            defer { seed.resetBytes(in: 0..<seed.count) }
            try seed.withUnsafeBytes { bytes in
                guard let address = bytes.baseAddress else { throw SigningFailure.message("Clé vide refusée.") }
                try require(SecKeychainAddGenericPassword(chain, UInt32(service.utf8.count), service, UInt32(account.utf8.count), account, UInt32(bytes.count), address, nil))
            }
            return value
        }
        try require(status)
        guard let pointer, length == 32 else {
            if let pointer { SecKeychainItemFreeContent(nil, pointer) }
            throw SigningFailure.message("La clé du trousseau Inboxy a un format inattendu.")
        }
        defer { SecKeychainItemFreeContent(nil, pointer) }
        var seed = Data(bytes: pointer, count: Int(length))
        defer { seed.resetBytes(in: 0..<seed.count) }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let mode = args.first, ["initialize", "public-key", "tool"].contains(mode) else {
                throw SigningFailure.message("Utilisation : initialize Info.plist | public-key | tool sign_update arguments…")
            }
            // Check the exact official executable BEFORE accessing any private key.
            if mode == "tool" {
                guard args.count >= 3 else { throw SigningFailure.message("Outil et arguments manquants.") }
                let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: args[1]))).map { String(format: "%02x", $0) }.joined()
                guard digest == officialToolHash else { throw SigningFailure.message("Outil de signature différent de la distribution officielle Sparkle 2.10.0 attendue.") }
            }
            let chain = try open(create: mode == "initialize")
            let privateKey = try key(in: chain, create: mode == "initialize")
            let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
            switch mode {
            case "initialize":
                guard args.count == 2 else { throw SigningFailure.message("Chemin Info.plist manquant.") }
                let url = URL(fileURLWithPath: args[1])
                guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any], plist["CFBundleIdentifier"] as? String == "fr.aeris.mail.prototype" else {
                    throw SigningFailure.message("Le fichier indiqué n’est pas le projet Inboxy.")
                }
                plist["SUPublicEDKey"] = publicKey
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url, options: .atomic)
                print("Clé Inboxy prête ; seule sa clé publique est intégrée au projet.")
            case "public-key": print(publicKey)
            default:
                let process = Process()
                process.executableURL = URL(fileURLWithPath: args[1])
                process.arguments = ["--ed-key-file", "-"] + Array(args.dropFirst(2))
                let input = Pipe(); process.standardInput = input
                try process.run()
                var secretInput = Data((privateKey.rawRepresentation.base64EncodedString() + "\n").utf8)
                defer { secretInput.resetBytes(in: 0..<secretInput.count) }
                try input.fileHandleForWriting.write(contentsOf: secretInput)
                try input.fileHandleForWriting.close()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw SigningFailure.message("La signature ou sa vérification a échoué.") }
            }
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }
}
