import SwiftUI
import AppKit
import Sparkle

@MainActor final class AutomaticUpdater: NSObject, ObservableObject, SPUUserDriver, NSWindowDelegate {
    enum Phase: Equatable {
        case idle, checking, downloading(Double?), verifying, installing, finished, cancelled, failed(String)
        var busy: Bool {
            switch self { case .checking, .downloading, .verifying, .installing: return true; default: return false }
        }
        var title: String {
            switch self {
            case .idle, .checking: return "Préparation de la mise à jour…"
            case .downloading: return "Téléchargement de la nouvelle version…"
            case .verifying: return "Vérification et préparation…"
            case .installing: return "Installation et relancement d’Inboxy…"
            case .finished: return "Mise à jour terminée"
            case .cancelled: return "Mise à jour annulée"
            case .failed: return "La mise à jour n’a pas abouti"
            }
        }
    }
    @Published private(set) var phase: Phase = .idle
    @Published var isPresented = false
    @Published private(set) var canCancel = false
    @Published private(set) var canRetryTermination = false
    private var updater: SPUUpdater?
    private var expectedVersion: String?
    private var cancellation: (() -> Void)?
    private var terminationRetry: (() -> Void)?
    private var received: UInt64 = 0
    private var expectedLength: UInt64 = 0
    private let hostBundle: Bundle
    private let acceptsArchive: (URL, String) -> Bool
    private var progressWindow: NSWindow?

    init(hostBundle: Bundle = .main, acceptsArchive: @escaping (URL, String) -> Bool = AutomaticUpdatePolicy.trustedArchive) {
        self.hostBundle = hostBundle; self.acceptsArchive = acceptsArchive
    }
    func install(_ offer: AppUpdateOffer) {
        isPresented = true
        presentProgressWindow()
        guard !phase.busy else { return }
        expectedVersion = offer.version
        phase = .checking; canCancel = false; canRetryTermination = false
        do {
            if updater == nil {
                let value = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: self, delegate: nil)
                try value.start()
                updater = value
            }
            guard let updater, updater.canCheckForUpdates else {
                phase = .failed("Une autre vérification est en cours. Réessayez dans un instant.")
                return
            }
            updater.checkForUpdates()
        } catch { phase = .failed(error.localizedDescription) }
    }
    func cancel() {
        guard canCancel, let cancellation else { return }
        self.cancellation = nil; canCancel = false; phase = .cancelled
        expectedVersion = nil
        cancellation()
    }
    func retryTermination() { terminationRetry?() }
    private func presentProgressWindow() {
        if let progressWindow { progressWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 546, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mise à jour d’Inboxy"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: AutomaticUpdateProgress(updater: self))
        window.center()
        progressWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    func closeProgress() {
        guard !phase.busy else { return }
        isPresented = false; progressWindow?.close(); progressWindow = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !phase.busy }
    func windowWillClose(_ notification: Notification) { isPresented = false; progressWindow = nil }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking; self.cancellation = cancellation; canCancel = true
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let expectedVersion, appcastItem.displayVersionString == expectedVersion,
              !appcastItem.isInformationOnlyUpdate, appcastItem.installationType == "application",
              let url = appcastItem.fileURL, acceptsArchive(url, expectedVersion) else {
            phase = .failed("La publication signée ne correspond pas à la version demandée. Réessayez une fois la publication terminée.")
            canCancel = false; reply(.skip); return
        }
        // The user's click explicitly authorizes this update, including its restart.
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        phase = .failed("Le téléchargement automatique n’est pas disponible pour le moment. Réessayez dans un instant.")
        canCancel = false; acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        phase = .failed(error.localizedDescription)
        canCancel = false; acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received = 0; expectedLength = 0; phase = .downloading(nil)
        self.cancellation = cancellation; canCancel = true
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        phase = .downloading(expectedContentLength > 0 ? 0 : nil)
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (sum, overflow) = received.addingReportingOverflow(length)
        received = overflow ? UInt64.max : sum
        phase = .downloading(expectedLength > 0 ? min(1, Double(received) / Double(expectedLength)) : nil)
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil; canCancel = false; phase = .verifying
    }
    func showExtractionReceivedProgress(_ progress: Double) { phase = .verifying }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        phase = .installing; canCancel = false
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        canRetryTermination = !applicationTerminated
        terminationRetry = applicationTerminated ? nil : retryTerminatingApplication
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .finished; canRetryTermination = false; acknowledgement()
    }
    func dismissUpdateInstallation() {
        canCancel = false; cancellation = nil; terminationRetry = nil; canRetryTermination = false
        if phase.busy { phase = .cancelled }
    }
}

struct AutomaticUpdatePresentation: View {
    @ObservedObject var updater: AutomaticUpdater
    var body: some View {
        Color.clear
    }
}
struct AutomaticUpdateProgress: View {
    @ObservedObject var updater: AutomaticUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Mise à jour d’Inboxy", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.accent)
            Text(updater.phase.title).font(.system(size: 14, weight: .medium)).id(updater.phase.title)
            if case .downloading(let progress) = updater.phase {
                if let progress { ProgressView(value: progress); Text("\(Int(progress * 100)) %").font(.caption).monospacedDigit() }
                else { ProgressView().controlSize(.small) }
            } else if updater.phase.busy { ProgressView().controlSize(.small) }
            if case .failed(let message) = updater.phase {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                Text("L’application actuelle et vos comptes restent disponibles. Vous pouvez réessayer en cliquant sur la version.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("L’application se relancera automatiquement après l’installation. Vos comptes et réglages restent sur ce Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if updater.canRetryTermination { Button("Fermer Inboxy et poursuivre") { updater.retryTermination() } }
                if updater.canCancel { Button("Annuler") { updater.cancel() } }
                if !updater.phase.busy { Button("Fermer") { updater.closeProgress() }.buttonStyle(.borderedProminent) }
            }
        }.padding(28).frame(width: 490).tint(Palette.accent)
    }
}
