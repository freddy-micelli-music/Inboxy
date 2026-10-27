import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddAccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var email = ""
    @ViewState<String> private var name = ""
    @ViewState<String> private var group = "Travail"
    @ViewState<Bool> private var advanced = false
    @FocusState private var emailFocused: Bool
    var body: some View {
        if advanced {
            VStack(spacing: 0) {
                HStack { Button("← Connexion intégrée") { advanced = false }.disabled(model.connecting); Spacer() }.padding(.horizontal, 32).padding(.top, 20)
                APIAccountView()
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.accent); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                Text("Un compte. Son propre espace.").font(.system(size: 27, weight: .light))
                Text("Ajoutez votre adresse Gmail ou Google Workspace. La connexion s’ouvrira ici, dans Inboxy, dans un espace séparé de vos autres comptes.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Adresse e-mail Google", text: $email).textFieldStyle(.roundedBorder).focused($emailFocused).onSubmit { add() }
                    TextField("Nom du compte · facultatif", text: $name).textFieldStyle(.roundedBorder)
                    Picker("Groupe", selection: $group) { Text("Travail").tag("Travail"); Text("Personnel").tag("Personnel") }
                }
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "lock.shield").foregroundStyle(Palette.accent)
                    Text("Vos mots de passe sont saisis uniquement sur la page Google. L’adresse ci-dessus nomme le profil ; vérifiez le compte affiché par Gmail après connexion.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(15).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                Text("Connexion intégrée expérimentale : Google peut refuser ce navigateur. Créer le profil ne signifie pas que le compte est déjà connecté.").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Autre méthode : API Gmail…") { advanced = true }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Ouvrir Gmail dans Inboxy") { add() }.buttonStyle(.borderedProminent).disabled(AccountInput.email(email) == nil)
                }
            }.padding(32).frame(width: 540).tint(Palette.accent).onAppear { emailFocused = true }
        }
    }
    private func add() { guard AccountInput.email(email) != nil else { return }; model.addWebAccount(email: email, name: name, group: group) }
}

struct APIAccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var secret = ""
    @ViewState<String?> private var importError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent); Spacer(); Button { if model.connecting { model.auth.cancel() } else { dismiss() } } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            Text("Un nouvel univers.").font(.system(size: 29, weight: .light))
            Text("Connectez un compte Gmail ou Google Workspace. Chaque compte conserve ses propres identifiants dans le Trousseau de ce Mac.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            Divider()
            Text("CONFIGURATION GOOGLE · UNE FOIS PAR PROJET").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            Text("Activez l’API Gmail dans Google Cloud, créez un client OAuth « Application de bureau », puis importez son fichier JSON. En mode test, ajoutez les adresses concernées aux utilisateurs de test.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button("Importer le fichier JSON Google…") { importCredentials() }.disabled(model.connecting)
            TextField("ID client OAuth Google", text: $model.clientID).textFieldStyle(.roundedBorder).disabled(model.connecting)
            SecureField("Secret du client de bureau (si fourni)", text: $secret).textFieldStyle(.roundedBorder).disabled(model.connecting)
            Text("L’autorisation s’ouvre dans votre navigateur. Accès demandé : lecture des messages. Aucun mot de passe Google n’est saisi dans Inboxy.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            if let importError { Text(importError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Link("Ouvrir Google Cloud ↗", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!).font(.system(size: 11))
                Spacer()
                if model.connecting { ProgressView().controlSize(.small); Button("Annuler") { model.auth.cancel() } }
                else { Button("Continuer avec Google") { Task { await model.connect(secret: secret) } }.buttonStyle(.borderedProminent).disabled(!model.clientID.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".apps.googleusercontent.com")) }
            }
        }.padding(32).frame(width: 520).tint(Palette.accent).interactiveDismissDisabled(model.connecting)
    }
    private func importCredentials() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            guard let installed = root?["installed"] as? [String: Any], let id = installed["client_id"] as? String, id.hasSuffix(".apps.googleusercontent.com") else { throw AerisError.message("Ce JSON n’est pas un client OAuth Google de type Application de bureau.") }
            model.clientID = id; secret = installed["client_secret"] as? String ?? ""; importError = nil
        } catch { importError = error.localizedDescription }
    }
}

struct AccountSwitcherView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var query = ""
    @ViewState<UUID?> private var selection: UUID?
    @FocusState private var focused: Bool
    var matches: [MailAccount] { model.visibleAccounts.filter { query.isEmpty || ($0.name + $0.email).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.accent)
                TextField("Aller à un compte…", text: $query).textFieldStyle(.plain).font(.system(size: 19, weight: .light)).focused($focused).onSubmit { commit() }
                Button("Échap") { dismiss() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            List(selection: $selection) {
                ForEach(matches) { account in
                    HStack(spacing: 12) {
                        Avatar(name: account.name, color: account.color, size: 32)
                        VStack(alignment: .leading, spacing: 3) { Text(account.name).font(.system(size: 12, weight: .medium)); Text(account.email).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        if model.selectedID == account.id { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                    }.padding(.vertical, 5).tag(account.id).contentShape(Rectangle()).onTapGesture { model.select(account); dismiss() }
                }
            }.listStyle(.plain).frame(height: 320)
            HStack { Text("↑ ↓ pour parcourir · ↵ pour ouvrir"); Spacer(); Text("\(matches.count) comptes") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(16)
        }.frame(width: 540).tint(Palette.accent).onAppear { focused = true; selection = model.selectedID }
            .onChange(of: query) { selection = matches.first?.id }
            .onExitCommand { dismiss() }
    }
    private func commit() { if let account = matches.first(where: { $0.id == selection }) ?? matches.first { model.select(account); dismiss() } }
}

struct AerisSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<UUID?> private var editID: UUID?
    @ViewState<MailAccount?> private var removeAccount: MailAccount?
    @ViewState<String> private var accountName = ""
    @ViewState<String> private var accountGroup = "Travail"
    @ViewState<Bool> private var accountNotifications = true
    var body: some View {
        TabView {
            Form {
                Section("Votre espace") {
                    Picker("Apparence", selection: $model.appearance) { Text("Automatique").tag("system"); Text("Claire").tag("light"); Text("Sombre").tag("dark") }
                }
                Section("Notifications") {
                    HStack { Text(model.notificationStatus); Spacer(); Button("Autoriser les notifications") { Task { await model.requestNotifications() } } }
                    Text("Tous les comptes sont relevés automatiquement avec un cycle visé d’une minute pendant que l’application fonctionne. Les pastilles comptent les non lus de la réception. Les alertes système restent disponibles pour la méthode API. Aucune vérification après avoir quitté Inboxy.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Finder et messagerie") {
                    Text("Dans le Finder : clic droit sur un fichier → Services → Envoyer avec Inboxy… Choisissez ensuite le compte Gmail expéditeur.").font(.caption).foregroundStyle(.secondary)
                    Button("Utiliser Inboxy pour les liens e-mail") {
                        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "mailto") { error in
                            Task { @MainActor in model.alert = error?.localizedDescription ?? "Inboxy ouvrira désormais les liens e-mail avec le choix du compte expéditeur." }
                        }
                    }
                    Text("Ce bouton change la messagerie par défaut pour les liens mailto. Le partage de fichiers du Finder utilise le service Inboxy ci-dessus.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Raccourcis") {
                    LabeledContent("Changer de compte", value: "⌘ K")
                    LabeledContent("Compte précédent / suivant", value: "⌃ ⇧ ⇥ / ⌃ ⇥")
                    LabeledContent("Actualiser", value: "⌘ R")
                    LabeledContent("Nouveau message dans Gmail", value: "⌘ N")
                    LabeledContent("Ajouter un compte", value: "⌘ ⇧ N")
                    LabeledContent("Comptes 1 à 9", value: "⌘ 1 … ⌘ 9")
                }
            }.formStyle(.grouped).tabItem { Label("Général", systemImage: "slider.horizontal.3") }
            HStack(spacing: 0) {
                List(model.accounts, selection: $editID) { account in
                    VStack(alignment: .leading, spacing: 4) { Text(account.name); Text(account.email).font(.caption).foregroundStyle(.secondary) }.tag(account.id)
                }.frame(width: 225)
                Form {
                    if let id = editID, let account = model.accounts.first(where: { $0.id == id }) {
                        Text(account.email).font(.headline).textSelection(.enabled)
                        TextField("Nom", text: $accountName)
                        Picker("Groupe", selection: $accountGroup) { Text("Travail").tag("Travail"); Text("Personnel").tag("Personnel") }
                        if !account.usesWeb { Toggle("Notifications pour ce compte", isOn: $accountNotifications) }
                        else { Text("La pastille est relevée en arrière-plan chaque minute avec la session propre à ce profil, même s’il n’est pas affiché. Une connexion lente peut prolonger le cycle. Les notifications système nécessitent la méthode API optionnelle.").font(.caption).foregroundStyle(.secondary) }
                        Button("Enregistrer") { var changed = account; changed.name = accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? account.email : accountName; changed.group = accountGroup; changed.notifications = accountNotifications; model.update(changed) }
                        Divider()
                        Button(account.usesWeb ? "Retirer ce profil…" : "Révoquer et retirer ce compte…", role: .destructive) { removeAccount = account }
                        Text(account.usesWeb ? "Supprime le profil local et sa session web. Les messages Gmail sont conservés." : "Retire l’autorisation Google, les jetons locaux et le stockage web de ce compte.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Sélectionnez un compte connecté. Pour en ajouter un, utilisez + dans la fenêtre principale.").foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth: .infinity)
            }.tabItem { Label("Comptes", systemImage: "person.2") }
        }.frame(width: 700, height: 570).tint(Palette.accent)
            .onChange(of: editID) { _, id in if let account = model.accounts.first(where: { $0.id == id }) { accountName = account.name; accountGroup = account.group; accountNotifications = account.notifications } }
            .alert("Retirer ce compte ?", isPresented: Binding(get: { removeAccount != nil }, set: { if !$0 { removeAccount = nil } })) {
                Button("Annuler", role: .cancel) { removeAccount = nil }
                Button("Révoquer et retirer", role: .destructive) { if let account = removeAccount { Task { await model.remove(account) } }; removeAccount = nil }
            } message: { Text(removeAccount?.usesWeb == true ? "Le profil local et sa session web seront supprimés. Vos messages dans Gmail seront conservés." : "L’autorisation Google et les données locales de ce compte seront retirées. Vos messages dans Gmail seront conservés.") }
    }
}
