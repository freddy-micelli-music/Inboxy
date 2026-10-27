import SwiftUI
import AppKit
import UserNotifications
import CoreServices

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet {
            guard let model else { return }
            let waiting = pendingRequests; pendingRequests.removeAll()
            for request in waiting { model.receiveCompose(request) }
            if let error = pendingError { model.alert = error; pendingError = nil }
        }
    }
    private var pendingRequests: [MailComposeRequest] = []
    private var pendingError: String?
    private func accept(_ request: MailComposeRequest) {
        if let model { model.receiveCompose(request) } else { pendingRequests.append(request) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Inboxy" })?.makeKeyAndOrderFront(nil)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for document in urls where document.isFileURL && document.pathExtension.lowercased() == "seeviewmail" {
            do { accept(try MailComposeRequest(seeviewDocument: document)) }
            catch { if let model { model.alert = error.localizedDescription } else { pendingError = error.localizedDescription } }
        }
        let files = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() != "seeviewmail" }
        if !files.isEmpty { accept(MailComposeRequest(files: files)) }
        for url in urls where !url.isFileURL {
            if let request = MailComposeRequest(mailto: url) { accept(request) }
        }
    }
    @objc(sendFiles:userData:error:)
    func sendFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if files.isEmpty, let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            files = paths.map { URL(fileURLWithPath: $0) }
        }
        do {
            files = try MailComposeRequest.readableFiles(files)
            guard !files.isEmpty else { error.pointee = "Sélectionnez un ou plusieurs fichiers dans le Finder."; return }
            accept(MailComposeRequest(files: files))
        } catch let issue { error.pointee = issue.localizedDescription as NSString }
    }
    private var aboutWindow: NSWindow?
    func showAbout() {
        if aboutWindow == nil {
            let content = NSHostingView(rootView: InboxyAboutView())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "À propos d’Inboxy"
            window.isReleasedWhenClosed = false
            window.contentView = content
            window.setContentSize(content.fittingSize)
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        UNUserNotificationCenter.current().delegate = self
        NSApp.servicesProvider = self
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        NSUpdateDynamicServices()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["accountID"] as? String
        DispatchQueue.main.async { [weak self] in
            if let id, let uuid = UUID(uuidString: id), let model = self?.model, let account = model.accounts.first(where: { $0.id == uuid }) {
                model.select(account)
            }
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }
}

@main struct AerisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Inboxy", id: "main") {
            ContentView().environmentObject(model).onAppear { delegate.model = model }
        }.defaultSize(width: 1360, height: 850).windowStyle(.hiddenTitleBar).windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("À propos d’Inboxy") { delegate.showAbout() }
                }
                CommandGroup(replacing: .newItem) {
                    Button("Nouveau message dans Gmail") { model.openGmail(compose: true) }.keyboardShortcut("n")
                    Button("Ajouter un compte Google…") { model.showAdd = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                }
                CommandMenu("Comptes") {
                    Button("Changer de compte…") { model.showSwitcher = true }.keyboardShortcut("k")
                    Button("Compte suivant") { model.cycle(1) }.keyboardShortcut(.tab, modifiers: [.control])
                    Button("Compte précédent") { model.cycle(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                    Divider()
                    ForEach(0..<9) { index in
                        Button("Compte \(index + 1)") { if model.visibleAccounts.indices.contains(index) { model.select(model.visibleAccounts[index]) } }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    }
                }
                CommandGroup(after: .toolbar) {
                    Button("Agrandir le contenu") { model.changeZoom(0.1) }.keyboardShortcut("+", modifiers: .command).disabled(!model.canZoom)
                    Button("Agrandir le contenu (=)") { model.changeZoom(0.1) }.keyboardShortcut("=", modifiers: .command).disabled(!model.canZoom).hidden()
                    Button("Réduire le contenu") { model.changeZoom(-0.1) }.keyboardShortcut("-", modifiers: .command).disabled(!model.canZoom)
                    Button("Taille réelle du contenu") { model.resetZoom() }.keyboardShortcut("0", modifiers: .command).disabled(!model.canZoom)
                    Divider()
                    Button("Actualiser les messages") { model.refresh() }.keyboardShortcut("r")
                }
            }
        Settings { AerisSettingsView().environmentObject(model).preferredColorScheme(model.scheme) }
    }
}

private struct InboxyAboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 80, height: 80)
            }
            VStack(spacing: 6) {
                Text("Inboxy").font(.system(size: 28, weight: .bold))
                Text("LA BOITE À GMAIL.").font(.system(size: 12, weight: .medium)).italic().tracking(1.5)
            }
            (Text("Éditeur").bold() + Text(" : Frédéric Fantino"))
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 16) {
                Text("Inboxy est un logiciel indépendant de traitement et d'organisation des boîtes Gmail. Il n'est pas affilié à Google LLC.")
                Text("Merci d'utiliser Inboxy. Vos retours sont précieux pour faire évoluer l'application.")
            }.font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("© 2027 Fantino. Tous droits réservés.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(32).frame(width: 520)
    }
}
