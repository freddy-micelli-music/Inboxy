import Foundation
import AppKit
import WebKit

@main struct CoreChecks {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
            guard condition() else { throw AerisError.message("FAIL: " + description) }
            passed += 1; print("PASS: " + description)
        }
        let attachmentURL = URL(string: "https://mail.google.com/mail/u/0/?view=att&attid=0.1&disp=safe")!
        try check(GmailAttachmentRouting.attachmentURL(attachmentURL) && GmailAttachmentRouting.attachmentURL(URL(string: "https://doc-123-mail-attachment.googleusercontent.com/attachment/test")!), "Pièces jointes Gmail et serveur de fichiers Google reconnus")
        try check(["https://mail.google.com/mail/u/0/#inbox", "https://mail.google.com.evil.test/mail/?view=att", "https://example.test/attachment/file", "https://mail-attachment.googleusercontent.com.evil.test/a"].allSatisfy { !GmailAttachmentRouting.attachmentURL(URL(string: $0)!) }, "Liens ordinaires et domaines ressemblants exclus des pièces jointes")
        try check(GmailAttachmentRouting.blobFromGmail(URL(string: "blob:https://mail.google.com/test")!) && !GmailAttachmentRouting.blobFromGmail(URL(string: "blob:https://mail.google.com.evil.test/test")!), "Fichiers blob rattachés à l’origine Gmail exacte")
        let pdfResponse = HTTPURLResponse(url: attachmentURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf", "Content-Disposition": "inline"])!
        let htmlResponse = HTTPURLResponse(url: attachmentURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        let dispositionResponse = HTTPURLResponse(url: URL(string: "https://mail.google.com/document")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf", "Content-Disposition": "Attachment; filename=test.pdf"])!
        try check(GmailAttachmentRouting.downloadResponse(pdfResponse, canShow: true) && GmailAttachmentRouting.downloadResponse(dispositionResponse, canShow: true) && !GmailAttachmentRouting.downloadResponse(htmlResponse, canShow: true), "PDF joint et en-tête Attachment enregistrés, page HTML de connexion conservée comme navigation")
        try check(AttachmentFileStore.safeName("../../facture.pdf") == "facture.pdf" && AttachmentFileStore.safeName("C:\\dossier\\facture.pdf") == "facture.pdf" && AttachmentFileStore.safeName("..") == "Pièce jointe" && AttachmentFileStore.safeName(".secret\n.pdf") == "secret.pdf", "Nom de fichier limité à un élément visible, sans traversée de dossiers ni caractères de contrôle")
        try check(AttachmentFileStore.safeName(String(repeating: "é", count: 500)).utf8.count <= 220, "Nom de pièce jointe borné en octets UTF-8")
        try check(AttachmentFileStore.safeName("/") == "Pièce jointe" && AttachmentFileStore.safeName("a" + String(repeating: "\u{0301}", count: 500)) == "Pièce jointe", "Racine et caractère combiné démesuré remplacés par un nom de fichier valide")
        let downloadRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Inboxy-file-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: downloadRoot) }
        let fileStore = AttachmentFileStore(destination: downloadRoot)
        let firstFile = try fileStore.stage("facture.pdf")
        try Data("original".utf8).write(to: firstFile.file)
        let firstSaved = try fileStore.finish(firstFile)
        let duplicate = try fileStore.stage("facture.pdf")
        try Data("nouveau".utf8).write(to: duplicate.file)
        let secondSaved = try fileStore.finish(duplicate)
        let originalBytes = try Data(contentsOf: firstSaved)
        let newBytes = try Data(contentsOf: secondSaved)
        try check(firstSaved.lastPathComponent == "facture.pdf" && secondSaved.lastPathComponent == "facture (2).pdf" && originalBytes == Data("original".utf8) && newBytes == Data("nouveau".utf8), "Doublon renommé sans écraser ni modifier les octets du premier fichier")
        try check(!FileManager.default.fileExists(atPath: firstFile.directory.path) && !FileManager.default.fileExists(atPath: duplicate.directory.path), "Répertoires de préparation retirés après enregistrement réussi")
        let incomplete = try fileStore.stage("incomplet.pdf")
        try Data("partiel".utf8).write(to: incomplete.file)
        fileStore.discard(incomplete)
        try check(!FileManager.default.fileExists(atPath: incomplete.directory.path) && !FileManager.default.fileExists(atPath: downloadRoot.appendingPathComponent("incomplet.pdf").path), "Téléchargement incomplet retiré sans fichier final trompeur")
        let backupAccount = MailAccount(name: "Boîte à transférer", email: "transfer@example.test", group: "Travail", webOnly: true)
        let sampleCookie = HTTPCookie(properties: [.name: "synthetic-session", .value: "test-cookie-never-a-real-session", .domain: ".example.test", .path: "/", .secure: "TRUE", HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE", .expires: Date().addingTimeInterval(3600)])!
        let backupProfile = BackupProfile(account: backupAccount, cookies: [BackupCookie(sampleCookie)], localStorage: nil, credential: nil)
        let sampleBackup = AccountBackup(profiles: [backupProfile])
        let protectedBackup = try BackupArchive.encrypt(sampleBackup, password: "test-only-password")
        let recoveredBackup = try BackupArchive.decrypt(protectedBackup, password: "test-only-password")
        try check(recoveredBackup.profiles.first?.account == backupAccount && recoveredBackup.profiles.first?.cookies.first?.value == sampleCookie.value, "Sauvegarde chiffrée : comptes et session synthétique restaurés")
        let recoveredCookie = try recoveredBackup.profiles[0].cookies[0].cookie()
        try check(recoveredCookie.isSecure && recoveredCookie.isHTTPOnly && recoveredCookie.domain == sampleCookie.domain && recoveredCookie.expiresDate != nil, "Cookies sécurisés et HttpOnly conservés")
        try check(protectedBackup.range(of: Data(backupAccount.email.utf8)) == nil && protectedBackup.range(of: Data(sampleCookie.value.utf8)) == nil, "Aucune adresse ni session lisible dans le fichier chiffré")
        let secondProtectedBackup = try BackupArchive.encrypt(sampleBackup, password: "test-only-password")
        try check(protectedBackup != secondProtectedBackup, "Sel et nonce aléatoires pour chaque sauvegarde")
        var wrongPassword = false
        do { _ = try BackupArchive.decrypt(protectedBackup, password: "wrong-password") } catch { wrongPassword = true }
        try check(wrongPassword, "Mot de passe incorrect refusé sans restauration")
        var modifiedEnvelope = try JSONSerialization.jsonObject(with: protectedBackup) as! [String: Any]
        var modifiedSealed = Data(base64Encoded: modifiedEnvelope["sealed"] as! String)!
        modifiedSealed[modifiedSealed.count / 2] ^= 1
        modifiedEnvelope["sealed"] = modifiedSealed.base64EncodedString()
        var modificationRejected = false
        do { _ = try BackupArchive.decrypt(JSONSerialization.data(withJSONObject: modifiedEnvelope), password: "test-only-password") } catch { modificationRejected = true }
        try check(modificationRejected, "Archive altérée rejetée par l’authentification du chiffrement")
        var invalidBackupHeader = try JSONSerialization.jsonObject(with: protectedBackup) as! [String: Any]
        invalidBackupHeader["rounds"] = Int.max
        var invalidHeaderRejected = false
        do { _ = try BackupArchive.decrypt(JSONSerialization.data(withJSONObject: invalidBackupHeader), password: "test-only-password") } catch { invalidHeaderRejected = true }
        try check(invalidHeaderRejected, "Paramètres de dérivation inconnus refusés avant tout calcul")
        var plainBackupRejected = false
        do { _ = try BackupArchive.decrypt(JSONEncoder().encode(sampleBackup), password: "test-only-password") } catch { plainBackupRejected = true }
        try check(plainBackupRejected, "Import non chiffré refusé")
        var shortPasswordRejected = false
        do { _ = try BackupArchive.encrypt(sampleBackup, password: "short") } catch { shortPasswordRejected = true }
        try check(shortPasswordRejected, "Mot de passe de sauvegarde trop court refusé")
        var duplicateBackupRejected = false
        do { try AccountBackup(profiles: [backupProfile, backupProfile]).validate() } catch { duplicateBackupRejected = true }
        try check(duplicateBackupRejected, "Profils dupliqués dans une sauvegarde rejetés")
        var caseDuplicate = backupAccount; caseDuplicate.email = "TRANSFER@example.test"
        try check(sampleBackup.newProfiles(existing: [caseDuplicate]).isEmpty && sampleBackup.newProfiles(existing: []).count == 1, "Fusion sans écraser un compte existant, adresse insensible à la casse")
        var apiProfile = backupProfile
        apiProfile.account.webOnly = false
        apiProfile.credential = GoogleToken(accessToken: "synthetic-access", refreshToken: "synthetic-refresh", expiresAt: Date(), clientID: "synthetic.apps.googleusercontent.com", clientSecret: "synthetic-client")
        let apiProtected = try BackupArchive.encrypt(AccountBackup(profiles: [apiProfile]), password: "test-only-password")
        let apiRecovered = try BackupArchive.decrypt(apiProtected, password: "test-only-password")
        try check(apiRecovered.profiles[0].credential?.refreshToken == "synthetic-refresh" && apiProtected.range(of: Data("synthetic-refresh".utf8)) == nil, "Jeton API synthétique chiffré et décodé sans exposition en clair")
        let panelSizes = SidebarPanelLayout.sizes(available: 900, weights: [0.3, 0.47, 0.23])
        try check(abs(panelSizes.reduce(0, +) - 900) < 0.001 && zip(panelSizes, SidebarPanelLayout.minima).allSatisfy { $0 >= $1 }, "Panneaux : hauteur totale et tailles minimales conservées")
        let constrainedSizes = SidebarPanelLayout.sizes(available: 400, weights: [0.01, 0.98, 0.01])
        try check(constrainedSizes[0] >= 55 && constrainedSizes[1] >= 135 && constrainedSizes[2] >= 45 && abs(constrainedSizes.reduce(0, +) - 400) < 0.001, "Réduction des blocs sans cacher le panneau Personnel ni les dossiers")
        try check(SidebarPanelLayout.validWeights([.nan, 0, -1]) == SidebarPanelLayout.defaults && SidebarPanelLayout.sizes(available: .nan, weights: []).allSatisfy { $0 == 0 }, "Dimensions invalides neutralisées")
        let smallSizes = SidebarPanelLayout.sizes(available: 100, weights: SidebarPanelLayout.defaults)
        try check(smallSizes.allSatisfy { $0 >= 0 } && abs(smallSizes.reduce(0, +) - 100) < 0.001, "Très petite fenêtre sans débordement ni hauteur négative")
        try check(ProgramVersion("0.3.10")! > ProgramVersion("v0.3.9")! && ProgramVersion("1.0.0")! > ProgramVersion("0.99.99")!, "Versions comparées numériquement, y compris après neuf correctifs")
        try check(ProgramVersion("v0.3.7") == ProgramVersion("0.3.7"), "Préfixe de version GitHub normalisé")
        try check(["0.3", "0.03.7", "0.3.7-beta", "0.3.7+build", " 0.3.7", "0.3.-7", "0.3.999999999999999999"].allSatisfy { ProgramVersion($0) == nil }, "Versions incomplètes, préversions et nombres invalides rejetés")
        let updateTag = "v0.3.8"
        let updatePage = "https://github.com/freddy-micelli-music/Inboxy/releases/tag/" + updateTag
        let updateAsset = "Inboxy-0.3.8-macOS.zip"
        let updateDownload = "https://github.com/freddy-micelli-music/Inboxy/releases/download/" + updateTag + "/" + updateAsset
        let releaseFixture: [String: Any] = ["tag_name": updateTag, "html_url": updatePage, "draft": false, "prerelease": false, "assets": [["name": updateAsset, "state": "uploaded", "size": 1024, "browser_download_url": updateDownload]]]
        let updateData = try JSONSerialization.data(withJSONObject: releaseFixture)
        let offer = try AppUpdateChecker.offer(from: updateData, currentVersion: "0.3.7")
        try check(offer?.version == "0.3.8" && offer?.releaseURL.absoluteString == updatePage, "Nouvelle version publiée avec installateur disponible et lien exact")
        let sameVersion = try AppUpdateChecker.offer(from: updateData, currentVersion: "0.3.8")
        let newerVersion = try AppUpdateChecker.offer(from: updateData, currentVersion: "0.4.0")
        try check(sameVersion == nil && newerVersion == nil, "Version égale ou plus ancienne sans fausse mise à jour")
        var invalidReleases: [[String: Any]] = []
        for field in ["draft", "prerelease"] { var invalid = releaseFixture; invalid[field] = true; invalidReleases.append(invalid) }
        var noInstaller = releaseFixture; noInstaller["assets"] = []; invalidReleases.append(noInstaller)
        var wrongSite = releaseFixture; wrongSite["html_url"] = "https://github.com.evil.test/freddy-micelli-music/Inboxy/releases/tag/v0.3.8"; invalidReleases.append(wrongSite)
        var wrongDownload = releaseFixture; wrongDownload["assets"] = [["name": updateAsset, "state": "uploaded", "size": 1024, "browser_download_url": "https://example.test/" + updateAsset]]; invalidReleases.append(wrongDownload)
        var refusedUpdates = 0
        for fixture in invalidReleases {
            do { _ = try AppUpdateChecker.offer(from: JSONSerialization.data(withJSONObject: fixture), currentVersion: "0.3.7") }
            catch { refusedUpdates += 1 }
        }
        try check(refusedUpdates == invalidReleases.count, "Brouillons, préversions, installateur absent et liens externes rejetés")
        var badJSONRejected = false
        do { _ = try AppUpdateChecker.offer(from: Data("not JSON".utf8), currentVersion: "0.3.7") } catch { badJSONRejected = true }
        try check(badJSONRejected, "Réponse de mise à jour illisible distinguée d’une application à jour")
        let updateConfiguration = URLSessionConfiguration.ephemeral
        updateConfiguration.protocolClasses = [UpdateCheckProtocol.self]
        let updateSession = URLSession(configuration: updateConfiguration)
        UpdateCheckProtocol.responseCode = 200; UpdateCheckProtocol.responseData = updateData
        let fetchedOffer = try await AppUpdateChecker.latest(currentVersion: "0.3.7", session: updateSession)
        try check(fetchedOffer == offer && UpdateCheckProtocol.lastRequest?.url == AppUpdateChecker.endpoint && UpdateCheckProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil && UpdateCheckProtocol.lastRequest?.httpBody == nil, "Vérification publique sans authentification ni donnée de compte")
        UpdateCheckProtocol.responseCode = 403
        var rateLimitRejected = false
        do { _ = try await AppUpdateChecker.latest(currentVersion: "0.3.7", session: updateSession) } catch { rateLimitRejected = true }
        try check(rateLimitRejected, "Limite GitHub traitée comme indisponibilité, pas comme version à jour")
        UpdateCheckProtocol.networkFailure = true
        var offlineRejected = false
        do { _ = try await AppUpdateChecker.latest(currentVersion: "0.3.7", session: updateSession) } catch { offlineRejected = true }
        try check(offlineRejected, "Absence de réseau sans fausse annonce de version à jour")
        updateSession.invalidateAndCancel()
        let automaticURL = "https://github.com/freddy-micelli-music/Inboxy/releases/download/v0.3.11/Inboxy-0.3.11-Update.zip"
        try check(AutomaticUpdatePolicy.trustedArchive(URL(string: automaticURL)!, version: "0.3.11"), "Installation automatique limitée à l’archive dédiée de la version annoncée")
        let rejectedArchives = [automaticURL.replacingOccurrences(of: "https:", with: "http:"), automaticURL.replacingOccurrences(of: "github.com", with: "github.com.evil.test"), automaticURL + "?download=1", automaticURL.replacingOccurrences(of: "-Update.zip", with: "-macOS.zip"), automaticURL.replacingOccurrences(of: "v0.3.11/", with: "v0.3.10/"), automaticURL.replacingOccurrences(of: "github.com/", with: "user@github.com/")]
        try check(rejectedArchives.allSatisfy { !AutomaticUpdatePolicy.trustedArchive(URL(string: $0)!, version: "0.3.11") }, "Archives HTTP, tierces, ambiguës ou d’une autre version refusées")
        let automaticDriver = AutomaticUpdater()
        var cancellationCount = 0
        automaticDriver.showDownloadInitiated { cancellationCount += 1 }
        automaticDriver.showDownloadDidReceiveExpectedContentLength(100)
        automaticDriver.showDownloadDidReceiveData(ofLength: UInt64.max)
        automaticDriver.showDownloadDidReceiveData(ofLength: 20)
        try check(automaticDriver.phase == .downloading(1), "Progression bornée même en cas de longueur excessive sans dépassement entier")
        automaticDriver.cancel(); automaticDriver.cancel()
        try check(cancellationCount == 1 && automaticDriver.phase == .cancelled && !automaticDriver.canCancel, "Annulation unique du téléchargement avant installation")
        automaticDriver.showDownloadInitiated { cancellationCount += 1 }
        automaticDriver.showDownloadDidStartExtractingUpdate()
        automaticDriver.cancel()
        try check(cancellationCount == 1 && automaticDriver.phase == .verifying && !automaticDriver.canCancel, "Annulation désactivée après le début de préparation de l’installation")
        var acknowledged = false
        automaticDriver.showUpdaterError(AerisError.message("Signature de test refusée")) { acknowledged = true }
        automaticDriver.dismissUpdateInstallation()
        try check(acknowledged && automaticDriver.phase == .failed("Signature de test refusée") && !automaticDriver.canCancel, "Échec conservé à l’écran après le nettoyage du moteur de mise à jour")
        try check(OAuthTools.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 — vecteur RFC 7636")
        try check(WebSessions.boundedZoom(0.01) == 0.5 && WebSessions.boundedZoom(9) == 2 && WebSessions.boundedZoom(.nan) == 1, "Zoom borné entre 50 et 200 pour cent, valeur invalide neutralisée")
        try check(WebSessions.boundedZoom(1.1 - 0.1) == 1, "Zoom sans dérive des décimales")
        try check(GmailMailboxMetadata.avatarURL("https://lh3.googleusercontent.com/a/photo") != nil && GmailMailboxMetadata.avatarURL("https://lh3.google.com/u/0/ogw/photo") != nil, "Photo Google acceptée")
        try check(["https://ssl.gstatic.com/gb/images/silhouette.png", "http://lh3.googleusercontent.com/a", "https://googleusercontent.com.evil.test/a", "https://evil.test/googleusercontent.com/a", "https://user@lh3.googleusercontent.com/a"].allSatisfy { GmailMailboxMetadata.avatarURL($0) == nil }, "Photo limitée aux véritables hôtes Google HTTPS")
        let calendarAccount = MailAccount(name: "Agenda", email: "studio+agenda@example.test", group: "Travail", colorIndex: 0)
        let calendar = URLComponents(url: WebSessions.calendarURL(account: calendarAccount), resolvingAgainstBaseURL: false)!
        try check(calendar.host == "calendar.google.com" && calendar.queryItems?.first(where: { $0.name == "authuser" })?.value == calendarAccount.email, "Agenda ciblé sur le compte sans altérer son adresse")
        let extraFolders = GmailMailboxMetadata.navigationItems([
            ["title": "Été + projets", "href": "https://mail.google.com/mail/u/3/#label/%C3%89t%C3%A9%2Bprojets"],
            ["title": "Copie", "href": "https://mail.google.com/mail/u/0/#label/%C3%89t%C3%A9%2Bprojets"],
            ["title": "Spam", "href": "https://mail.google.com/mail/u/0/#spam"],
            ["title": "Réception", "href": "https://mail.google.com/mail/u/0/#inbox"],
            ["title": "Externe", "href": "https://evil.test/mail/#label/test"],
            ["title": "Commande", "href": "javascript:alert(1)"]
        ])
        try check(extraFolders.count == 2 && extraFolders[0].title == "Été + projets" && extraFolders[1].fragment == "spam", "Dossiers supplémentaires dédupliqués, liens externes et doublons natifs exclus")
        let extraURL = URLComponents(url: extraFolders[0].url(account: calendarAccount), resolvingAgainstBaseURL: false)!
        try check(extraURL.percentEncodedFragment == "label/%C3%89t%C3%A9%2Bprojets" && extraURL.queryItems?.first?.value == calendarAccount.email && extraURL.path == "/mail/u/0/", "Libellé encodé conservé et navigation rattachée au compte sélectionné")
        try check(GmailMailboxMetadata.navigationItems([["title": " ", "href": "https://mail.google.com/mail/u/0/#spam"]]).isEmpty, "Dossier sans nom ignoré")
        let utcDate = ISO8601DateFormatter()
        let calendarNow = utcDate.date(from: "2026-10-26T12:00:00Z")!
        func calendarRow(_ id: String, _ time: String, key: Int = 29018, cancelled: Bool = false) -> [String: Any] {
            ["id": id, "title": "Rendez-vous de test", "label": time + ", Rendez-vous de test, 26 octobre 2026", "dayKey": key, "cancelled": cancelled, "timeZone": "UTC"]
        }
        let upcomingRows = [calendarRow("past", "De 09:15 à 09:30"), calendarRow("later", "De 19:00 à 20:00"), calendarRow("next", "De 13:30 à 14:00"), calendarRow("next", "De 13:30 à 14:00"), calendarRow("cancelled", "De 12:30 à 13:00", cancelled: true)]
        let appointments = CalendarAppointmentMetadata.appointments(upcomingRows, now: calendarNow)
        try check(appointments.map(\.eventID) == ["next", "later"] && appointments[0].start == utcDate.date(from: "2026-10-26T13:30:00Z"), "Agenda : tri du prochain rendez-vous, passé/annulé exclus et doublons retirés")
        try check(CalendarAppointmentMetadata.dateComponents(key: 29018)?.year == 2026 && CalendarAppointmentMetadata.dateComponents(key: 29018)?.month == 10 && CalendarAppointmentMetadata.dateComponents(key: 29018)?.day == 26 && CalendarAppointmentMetadata.dateComponents(key: 28992) == nil, "Date Agenda décodée et jour invalide rejeté")
        let allDay = CalendarAppointmentMetadata.appointments([calendarRow("allday", "Jour entier", key: 29019)], now: calendarNow).first
        try check(allDay?.allDay == true && allDay?.announcement.contains("Journée entière") == true, "Événement sur la journée entière conservé sans heure inventée")
        try check(CalendarAppointmentMetadata.appointments([calendarRow("am", "9am to 10am"), calendarRow("pm", "1pm to 2pm")], now: calendarNow).map(\.eventID) == ["pm"], "Horaires de douze heures et filtre du passé")
        try check(CalendarAppointmentMetadata.appointments([calendarRow("bad", "De 29:00 à 30:00"), calendarRow("bad-date", "De 13:00 à 14:00", key: 0), calendarRow("javascript:bad", "De 14:00 à 15:00")], now: calendarNow).isEmpty, "Métadonnées Agenda invalides rejetées sans inventer de rendez-vous")
        let dst = CalendarAppointmentMetadata.appointments([calendarRow("dst", "De 01:30 à 02:30", key: 29017)], now: utcDate.date(from: "2026-10-25T00:00:00Z")!).first
        try check(dst?.start == utcDate.date(from: "2026-10-25T01:30:00Z"), "Lecture UTC de l’horaire sans ambiguïté au changement d’heure")
        var parisEvent = calendarRow("paris", "De 20:00 à 21:00")
        parisEvent["timeZone"] = "Europe/Paris"
        try check(CalendarAppointmentMetadata.appointments([parisEvent], now: calendarNow).first?.start == utcDate.date(from: "2026-10-26T19:00:00Z"), "Heure locale de Paris conservée sans décalage artificiel d’une heure")
        let random = try OAuthTools.random()
        try check(random.count == 43, "Vérificateur cryptographique de 256 bits")
        let code = try OAuthTools.callback("/oauth/callback?state=expected&code=a%2Bb%2Fc", state: "expected")
        try check(code == "a+b/c", "Décodage du code OAuth")
        for target in ["/oauth/callback?state=wrong&code=x", "/other?state=expected&code=x", "/oauth/callback?state=expected&state=wrong&code=x", "/oauth/callback?state=expected&error=access_denied", "/oauth/callback?state=expected"] {
            var rejected = false
            do { _ = try OAuthTools.callback(target, state: "expected") } catch { rejected = true }
            try check(rejected, "Rejet du retour invalide : " + target.components(separatedBy: "?")[0])
        }
        let form = String(data: formData(["code": "a+b &c=é"]), encoding: .utf8)!
        try check(form == "code=a%2Bb%20%26c%3D%C3%A9", "Encodage formulaire sans altérer +, &, = et Unicode")
        let original = "Un message : été 🌱"
        try check(Data(base64URL: Data(original.utf8).base64URL) == Data(original.utf8), "Base64URL UTF-8 sans padding")
        let payload = """
        {"id":"abc123","internalDate":"1000000","labelIds":["INBOX","UNREAD","STARRED"],"snippet":"Aperçu","payload":{"mimeType":"multipart/alternative","headers":[{"name":"from","value":"Camille <camille@example.test>"},{"name":"Subject","value":"Bonjour"}],"parts":[{"mimeType":"text/html","body":{"data":"PGI-aGk8L2I-"}},{"mimeType":"text/plain","body":{"data":"\(Data(original.utf8).base64URL)"}}]}}
        """
        let raw = try JSONDecoder().decode(GmailMessage.self, from: Data(payload.utf8))
        let parsed = raw.mail(accountID: UUID())
        try check(parsed.body == original && parsed.sender == "Camille" && parsed.senderEmail == "camille@example.test", "Message MIME multipart et en-têtes insensibles à la casse")
        try check(parsed.unread && parsed.starred && parsed.date.timeIntervalSince1970 == 1000, "Labels et date Gmail en millisecondes")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aeris-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AccountPersistence(root: root)
        let accounts = (0..<45).map { MailAccount(name: "Compte \($0)", email: "\($0)@example.test", group: "Travail", colorIndex: $0) }
        let legacyDemo = MailAccount(name: "Ancien exemple", email: "legacy@example.test", group: "Travail", isDemo: true)
        try repository.save(accounts + [legacyDemo])
        let restored = try repository.load()
        try check(restored == accounts && Set(restored.map(\.id)).count == 45, "45 comptes restaurés avec UUID stables ; démo exclue du disque")
        let movedDown = AccountOrdering.moving(accounts[0].id, relativeTo: accounts[2].id, after: true, in: accounts)
        try check(Array(movedDown.prefix(3).map(\.id)) == [accounts[1].id, accounts[2].id, accounts[0].id] && Set(movedDown.map(\.id)) == Set(accounts.map(\.id)), "Déplacement vers le bas sans perte ni doublon")
        let movedUp = AccountOrdering.moving(accounts[44].id, relativeTo: accounts[0].id, after: false, in: accounts)
        try repository.save(movedUp)
        let reorderedRestored = try repository.load()
        try check(reorderedRestored == movedUp && reorderedRestored.first == accounts[44], "Déplacement vers le haut et ordre conservé après restauration")
        var grouped = accounts
        grouped[2].group = "Personnel"
        let crossGroup = AccountOrdering.moving(grouped[0].id, relativeTo: grouped[2].id, after: false, in: grouped)
        try check(crossGroup[1].id == grouped[0].id && crossGroup[1].group == "Personnel" && crossGroup[1].email == grouped[0].email, "Déplacement entre groupes sans changer l’identité du profil")
        try check(AccountOrdering.moving(accounts[0].id, relativeTo: accounts[0].id, after: true, in: accounts) == accounts && AccountOrdering.moving(UUID(), relativeTo: accounts[0].id, after: false, in: accounts) == accounts, "Dépôt sur soi-même ou profil absent sans effet")
        let freshRepository = AccountPersistence(root: root.appendingPathComponent("fresh"))
        let freshAccounts = try freshRepository.load()
        try check(freshAccounts.isEmpty, "Première installation sans aucun compte fictif")
        let freshModel = AppModel(persistence: freshRepository)
        try check(freshModel.visibleAccounts.isEmpty && freshModel.selectedAccount == nil && freshModel.messages.isEmpty && freshModel.unread.isEmpty, "Premier lancement prêt pour la connexion du premier compte Gmail")
        let oldStoredData = try JSONEncoder().encode(accounts + [legacyDemo])
        try oldStoredData.write(to: repository.url)
        let migrated = try repository.load()
        let unchangedStoredData = try Data(contentsOf: repository.url)
        try check(migrated == accounts && unchangedStoredData == oldStoredData, "Ancien profil fictif ignoré sans changer les vrais comptes ni réécrire le fichier")
        let existingRepository = AccountPersistence(root: root.appendingPathComponent("existing"))
        let existingProfiles = accounts.prefix(2).map { account -> MailAccount in var value = account; value.webOnly = true; return value }
        try existingRepository.save(existingProfiles)
        let existingModel = AppModel(persistence: existingRepository)
        try check(existingModel.visibleAccounts == existingProfiles && existingModel.selectedID == existingProfiles.first?.id, "Installation existante : comptes, ordre et identité conservés")
        try check(AccountInput.email("  studio@gmail.com  ") == "studio@gmail.com", "Adresse de profil normalisée")
        try check(AccountInput.email("missing-at") == nil && AccountInput.email("a b@gmail.com") == nil && AccountInput.email("a@@gmail.com") == nil, "Refus des adresses de profil invalides")
        let legacyData = try JSONEncoder().encode(accounts)
        let legacy = try JSONDecoder().decode([MailAccount].self, from: legacyData)
        try check(legacy.allSatisfy { !$0.usesWeb }, "Anciens comptes API conservés sans champ webOnly")
        var webAccounts = accounts
        for index in webAccounts.indices { webAccounts[index].webOnly = true }
        try repository.save(webAccounts)
        let webRestored = try repository.load()
        try check(webRestored.count == 45 && webRestored.allSatisfy(\.usesWeb) && webRestored.map(\.id) == accounts.map(\.id), "45 profils Gmail intégrés persistants et distincts")
        let gmailURL = WebSessions.gmailURL(account: webAccounts[0])
        try check(MailFolder.allCases.last == .trash && MailFolder.trash.query == "in:trash" && GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#trash")) == .trash, "Corbeille reliée au dossier Gmail et placée après Envoyés")
        let source = URL(string: "https://mail.google.com/mail/u/0/#inbox")!
        try check(GmailNavigationRules.externalPage(URL(string: "https://www.google.com/url?q=https://example.test")!, from: source, activated: true) && GmailNavigationRules.externalPage(URL(string: "https://docs.google.com/document/d/test")!, from: source, activated: false, newWindow: true), "Liens Google de messages ouverts dans le navigateur")
        try check(GmailNavigationRules.externalPage(URL(string: "http://example.test/page")!, from: source, activated: true) && GmailNavigationRules.externalPage(URL(string: "https://example.test/redirect")!, from: source, activated: false), "Liens HTTP et redirections externes sortent de Gmail")
        try check(!GmailNavigationRules.externalPage(URL(string: "https://mail.google.com/mail/u/0/#sent")!, from: source, activated: true) && !GmailNavigationRules.externalPage(URL(string: "https://accounts.youtube.com/accounts/SetSID")!, from: URL(string: "https://accounts.google.com/signin"), activated: false, newWindow: true), "Dossiers internes et parcours de connexion restent dans leur profil")
        try check(!GmailNavigationRules.externalPage(URL(string: "javascript:alert(1)")!, from: source, activated: true), "Les protocoles exécutables ne sont pas envoyés au navigateur")
        let compose = MailComposeRequest(mailto: URL(string: "mailto:studio%2Btest@example.test?subject=Bonjour%20%26%20merci&body=Une%20ligne%0ADeux&attachment=file:///private/secret")!)!
        let composeURL = compose.gmailURL(account: webAccounts[0])
        let composeItems = URLComponents(url: composeURL, resolvingAgainstBaseURL: false)!.queryItems!
        try check(compose.to == "studio+test@example.test" && compose.subject == "Bonjour & merci" && compose.body == "Une ligne\nDeux" && compose.files.isEmpty && composeItems.first(where: { $0.name == "to" })?.value == compose.to && composeURL.absoluteString.contains("%2B"), "Liens mailto décodés sans altérer + et sans autoriser de pièce jointe locale")
        let shareFile = root.appendingPathComponent("pièce jointe.txt")
        try Data("Test local Inboxy".utf8).write(to: shareFile)
        let validFiles = try MailComposeRequest.readableFiles([shareFile, shareFile])
        try check(validFiles == [shareFile], "Fichiers Finder dédupliqués sans lire leur contenu")
        var rejectedFolder = false
        do { _ = try MailComposeRequest.readableFiles([root]) } catch { rejectedFolder = true }
        try check(rejectedFolder && MailComposeRequest(mailto: URL(string: "https://example.test")!) == nil, "Dossiers et faux liens mailto refusés")
        try check(gmailURL.host == "mail.google.com" && URLComponents(url: gmailURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "authuser" })?.value == webAccounts[0].email, "Gmail ouvert directement avec l’adresse du profil")
        try check(GmailNavigationRules.internalDocument(URL(string: "about:blank")!) && GmailNavigationRules.internalDocument(URL(string: "about:srcdoc")!), "Trames internes Gmail about:blank et about:srcdoc autorisées")
        try check(!GmailNavigationRules.internalDocument(URL(string: "javascript:alert(1)")!), "Une trame interne ne donne pas une autorisation générale aux autres protocoles")
        try check(GmailNavigationRules.googleHost("accounts.google.fr") && GmailNavigationRules.googleHost("accounts.google.co.uk"), "Redirections Google régionales reconnues")
        try check(["https://accounts.youtube.com/accounts/SetSID", "https://accounts.youtube.com/accounts/CheckConnection", "https://accounts.blogger.com/accounts/SetSID"].allSatisfy { GmailNavigationRules.googleHost(URL(string: $0)!.host!) }, "Étapes de connexion Google YouTube et Blogger reconnues")
        try check(!GmailNavigationRules.googleHost("accounts.youtube.com.evil.test") && !GmailNavigationRules.googleHost("evilaccounts.youtube.com") && !GmailNavigationRules.googleHost("sub.accounts.blogger.com") && !GmailNavigationRules.googleHost("www.youtube.com") && !GmailNavigationRules.googleHost("www.blogger.com"), "Exception limitée aux hôtes exacts de connexion Google")
        try check(!GmailNavigationRules.googleHost("accounts.google.com.evil.test") && !GmailNavigationRules.googleHost("evilgoogle.fr") && !GmailNavigationRules.googleHost("google.co.uk.evil.test"), "Domaines ressemblants exclus de la navigation Google")
        let cookieURL = URL(string: "https://accounts.google.com/CheckCookie?continue=private")!
        let interruption = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: [NSURLErrorFailingURLErrorKey: cookieURL])
        try check(GmailNavigationRules.cookieRedirectInterrupted(interruption, currentURL: nil), "Reprise ciblée d’une interruption de vérification des cookies Google")
        let otherInterruption = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://accounts.google.com/v3/signin/identifier")!])
        try check(!GmailNavigationRules.cookieRedirectInterrupted(otherInterruption, currentURL: cookieURL), "Pas de reprise automatique générique d’un formulaire de connexion")
        let wrongDomain = NSError(domain: "OtherErrorDomain", code: 102, userInfo: [:])
        try check(!GmailNavigationRules.cookieRedirectInterrupted(wrongDomain, currentURL: cookieURL), "Le même code dans un autre domaine n’est pas masqué")
        try check(GmailNavigationRules.cancelled(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)) && !GmailNavigationRules.cancelled(NSError(domain: "OtherErrorDomain", code: NSURLErrorCancelled)), "Annulations identifiées par domaine et code")
        let inboxURL = URL(string: "https://mail.google.com/mail/u/0/#inbox")!
        try check(GmailMailboxMetadata.folder(url: inboxURL) == .inbox && GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#inbox/message-id")!) == .inbox, "Dossier Réception reconnu dans la liste et dans un message")
        try check(GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#sent")!) == .sent && GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#starred")!) == .starred, "Dossiers Envoyés et Favoris reconnus depuis Gmail")
        try check(GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#search/in%3Ainbox+is%3Aunread")!) == .unread, "Recherche Gmail de non lus décodée")
        try check(GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#drafts")!) == nil && GmailMailboxMetadata.folder(url: URL(string: "https://mail.google.com/mail/u/0/#search/from%3Astudio")!) == nil, "Pas de sélection Réception inventée pour Brouillons ou une recherche")
        try check(GmailMailboxMetadata.folder(url: URL(string: "https://accounts.google.com/#inbox")!) == nil, "Une page de connexion ne devient pas une boîte Gmail")
        try check(GmailMailboxMetadata.titleCount("Boîte de réception (1 234) - compte - Gmail", url: inboxURL) == 1234 && GmailMailboxMetadata.titleCount("Inbox (2,345) - account - Gmail", url: inboxURL) == 2345, "Compteurs français et anglais avec séparateurs")
        try check(GmailMailboxMetadata.titleCount("Boîte de réception - compte - Gmail", url: inboxURL) == 0, "Zéro uniquement quand Gmail affiche une boîte prête sans compteur")
        try check(GmailMailboxMetadata.titleCount("Facture (2026) - compte - Gmail", url: inboxURL) == nil, "Le nombre d’un objet de message ne devient pas un compteur")
        try check(GmailMailboxMetadata.titleCount("Inbox (3) - account - Gmail", url: URL(string: "https://mail.google.com/mail/u/0/#sent")!) == nil, "Pas de remise à zéro du compteur depuis le titre d’un autre dossier")
        guard CommandLine.arguments.contains("--webkit") else {
            print("\(passed) contrôles réussis. Isolation WebKit : non exécutée (utiliser --webkit hors environnement restreint).")
            return
        }
        // Real WebKit cookie stores, no Google network requests and no user profiles modified.
        _ = NSApplication.shared
        let firstID = UUID(), secondID = UUID()
        let first = WKWebsiteDataStore(forIdentifier: firstID)
        let second = WKWebsiteDataStore(forIdentifier: secondID)
        let cookie = HTTPCookie(properties: [.domain: "aeris-check.invalid", .path: "/", .name: "session", .value: "only-first", .expires: Date().addingTimeInterval(3600), .secure: "TRUE"])!
        await first.httpCookieStore.setCookie(cookie)
        let ownCookies = await first.httpCookieStore.allCookies()
        let otherCookies = await second.httpCookieStore.allCookies()
        try check(ownCookies.contains { $0.name == "session" } && !otherCookies.contains { $0.name == "session" }, "Isolation réelle des cookies WebKit entre deux comptes")
        let reopened = WKWebsiteDataStore(forIdentifier: firstID)
        let reopenedCookies = await reopened.httpCookieStore.allCookies()
        try check(reopenedCookies.contains { $0.value == "only-first" }, "Réouverture du même stockage WebKit par UUID")
        let sessions = WebSessions()
        try check(sessions.capacity == 3, "Cache des vues web borné à 3")
        try await WKWebsiteDataStore.remove(forIdentifier: firstID)
        try await WKWebsiteDataStore.remove(forIdentifier: secondID)
        print("\(passed) contrôles réussis.")
    }
}

private final class UpdateCheckProtocol: URLProtocol {
    static var responseCode = 200
    static var responseData = Data()
    static var networkFailure = false
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { request.url == AppUpdateChecker.endpoint }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if Self.networkFailure { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
