import SwiftUI
@main struct SendReturnCheckApp: App {
    @ViewState var status = "Contrôle du retour après envoi… Aucun e-mail réel envoyé."
    var body: some Scene {
        WindowGroup("Inboxy · retour après envoi · test indépendant") {
            Text(status).padding(30).frame(width: 700, height: 360).textSelection(.enabled)
                .task {
                    do { try await SendReturnChecks.main() }
                    catch { SendReturnChecks.record("FAIL:",error.localizedDescription) }
                    status = SendReturnChecks.lines.joined(separator: "\n")
                    try? Data(status.utf8).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("InboxySendReturnChecks.log"))
                }
        }
    }
}
