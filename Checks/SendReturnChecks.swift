import Foundation
import WebKit
import AppKit

@MainActor final class DestinationCapture: NSObject, WKNavigationDelegate {
 var destination: URL?
 var capture = false
 func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
  if capture { destination = navigationAction.request.url; decisionHandler(.cancel) }
  else { decisionHandler(.allow) }
 }
}
enum SendReturnChecks {
    @MainActor static var lines: [String] = []
    @MainActor static func record(_ values: Any...) { lines.append(values.map { String(describing: $0) }.joined(separator: " ")) }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0,y: 0,width: 800,height: 600), configuration: config)
        web.loadHTMLString("""
        <html><body><button id="send" aria-label="Envoyer (⌘Entrée)">Envoyer</button>
        <div id="toast" role="alert"></div><div id="message">Message envoyé</div>
        <div id="editor" contenteditable="true">Brouillon synthétique</div></body></html>
        """, baseURL: URL(string: "https://mail.google.com/mail/u/3/")!)
        for _ in 0..<200 {
            if !web.isLoading, (try? await web.evaluateJavaScript("document.getElementById('send') !== null")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        record("Origin:", try await web.evaluateJavaScript("location.href"))
        let _: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(GmailSendCompletion.observerScript + "\nreturn true;", arguments: [:], in: nil, in: GmailMailboxTracker.world) { result in
                continuation.resume(with: result)
            }
        }
        var passed = 0
        func run(_ js: String, expected: String, _ label: String) async throws {
            _ = try await web.evaluateJavaScript("(function(){" + js + ";return true;})()")
            try await Task.sleep(nanoseconds: 350_000_000)
            let route = try await web.evaluateJavaScript("location.hash") as? String
            guard route == expected else { throw AerisError.message("FAIL: \(label) · \(route ?? "nil")") }
            passed += 1; record("PASS:", label)
        }
        try await run("location.hash='sent';document.getElementById('toast').textContent='Message envoyé.'", expected: "#sent", "Ancienne confirmation sans tentative d’envoi : pas de retour")
        try await run("document.getElementById('send').click();document.getElementById('message').textContent='Message envoyé.'", expected: "#sent", "Clic Envoyer et contenu du message : aucun faux succès")
        try await run("document.getElementById('toast').textContent='Impossible d’envoyer le message';", expected: "#sent", "Erreur d’envoi : brouillon et dossier conservés")
        try await run("document.getElementById('toast').textContent='Message envoyé. Annuler Afficher le message';", expected: "#inbox", "Confirmation française après tentative : retour en boîte de réception")
        try await run("location.hash='starred';document.getElementById('toast').textContent='';", expected: "#starred", "Une seule navigation par confirmation")
        try await run("document.getElementById('send').setAttribute('aria-label','Send');document.getElementById('send').click();document.getElementById('toast').textContent='Message sent. Undo View message';", expected: "#inbox", "Confirmation anglaise : retour en boîte de réception")
        try await run("location.hash='sent';document.getElementById('toast').textContent='';", expected: "#sent", "Préparation du test au clavier")
        try await run("document.getElementById('editor').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',metaKey:true,bubbles:true}));document.getElementById('toast').textContent='Votre message a été envoyé.';", expected: "#inbox", "Envoi par Commande Entrée : confirmation puis retour")
        try await run("location.hash='sent';document.getElementById('toast').textContent='';", expected: "#sent", "Préparation de l’envoi programmé")
        try await run("document.getElementById('send').click();document.getElementById('toast').textContent='Envoi programmé';", expected: "#sent", "Message programmé : aucun faux envoi confirmé")
        record("Final URL:", web.url?.absoluteString ?? "nil")
        guard web.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "mail/u/3" else { throw AerisError.message("Le compte a changé") }

        func standaloneCase(_ action: String, shouldReturn: Bool, label: String) async throws {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            let page = WKWebView(frame: NSRect(x:0,y:0,width:800,height:600),configuration:config)
            let delegate = DestinationCapture(); page.navigationDelegate = delegate
            page.loadHTMLString("<html><body><button id='send' aria-label='Envoyer'>Envoyer</button><div id='toast' role='alert'></div><div id='editor' contenteditable='true'>Brouillon synthétique</div></body></html>", baseURL: URL(string:"https://mail.google.com/mail/u/3/?authuser=atelier%40example.test&hl=fr&view=cm&fs=1&to=destinataire%40example.test&su=Sujet&body=Texte")!)
            for _ in 0..<200 {
                if !page.isLoading, (try? await page.evaluateJavaScript("document.getElementById('send') !== null")) as? Bool == true { break }
                try await Task.sleep(nanoseconds:50_000_000)
            }
            let _: Any? = try await withCheckedThrowingContinuation { continuation in
                page.callAsyncJavaScript(GmailSendCompletion.observerScript + "\nreturn true;", arguments:[:],in:nil,in:GmailMailboxTracker.world) { continuation.resume(with:$0) }
            }
            delegate.capture = true
            _ = try await page.evaluateJavaScript("(function(){" + action + ";return true;})()")
            try await Task.sleep(nanoseconds:500_000_000)
            if shouldReturn {
                guard let destination=delegate.destination, let parts=URLComponents(url:destination,resolvingAgainstBaseURL:false),
                  destination.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "mail/u/3", parts.fragment == "inbox",
                  parts.queryItems == [URLQueryItem(name:"authuser",value:"atelier@example.test"),URLQueryItem(name:"hl",value:"fr")] else {
                    throw AerisError.message("FAIL: \(label), destination=\(delegate.destination?.absoluteString ?? "nil")")
                }
            } else if delegate.destination != nil { throw AerisError.message("FAIL: \(label): retour prématuré") }
            passed += 1; record("PASS:",label)
        }
        try await standaloneCase("document.getElementById('send').click();document.getElementById('toast').textContent='Message envoyé. Annuler';",shouldReturn:true,label:"Lien navigateur : confirmation puis vraie réception, paramètres de rédaction retirés")
        try await standaloneCase("document.getElementById('send').click();document.getElementById('editor').remove();document.getElementById('toast').remove();const p=document.createElement('p');p.textContent='Votre message a été envoyé.';document.body.append(p);",shouldReturn:true,label:"Rédaction séparée : confirmation française sans rôle ARIA")
        try await standaloneCase("document.getElementById('send').click();document.getElementById('editor').remove();document.getElementById('toast').remove();const p=document.createElement('p');p.textContent='Your message has been sent.';document.body.append(p);",shouldReturn:true,label:"Rédaction séparée : confirmation anglaise sans rôle ARIA")
        try await standaloneCase("document.getElementById('send').click();document.getElementById('toast').textContent='Impossible d’envoyer le message';",shouldReturn:false,label:"Rédaction séparée : erreur conservée")
        try await standaloneCase("document.getElementById('send').click();document.getElementById('toast').textContent='Envoi programmé';",shouldReturn:false,label:"Rédaction séparée : envoi programmé conservé")
        try await standaloneCase("document.getElementById('send').click();document.getElementById('editor').innerHTML='<p>Message envoyé.</p>';",shouldReturn:false,label:"Texte du brouillon : pas de fausse confirmation")
        try await standaloneCase("document.getElementById('editor').remove();document.getElementById('toast').textContent='Message envoyé.';",shouldReturn:false,label:"Confirmation sans tentative : pas de navigation")
        record("\(passed) contrôles WebKit réussis ; aucun e-mail envoyé.")

    }
}
