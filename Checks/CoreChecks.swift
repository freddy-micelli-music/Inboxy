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
        try repository.save(accounts + DemoData.accounts())
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
        try check(DemoData.accounts().count == 36, "36 comptes dans la démonstration")
        let demo = DemoData.accounts()[0]
        try check(DemoData.messages(for: demo).allSatisfy { $0.accountID == demo.id }, "Messages rattachés uniquement à leur compte")
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
