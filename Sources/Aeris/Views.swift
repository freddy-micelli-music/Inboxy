import SwiftUI
import AppKit
import UniformTypeIdentifiers

private extension Color {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let ink = Color.primary
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var showPlacement = false
    @ViewState private var compactHeader = false
    var body: some View {
        let placement = model.placement
        let layout = placement.horizontal ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            if placement.beforeWorkspace { navigation }
            workspace
            if !placement.beforeWorkspace { navigation }
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(Palette.accent)
        .preferredColorScheme(model.scheme)
        .sheet(isPresented: $model.showAdd) { AddAccountView().environmentObject(model) }
        .sheet(isPresented: $model.showSwitcher) { AccountSwitcherView().environmentObject(model) }
        .alert("Inboxy", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("OK") { model.alert = nil } } message: { Text(model.alert ?? "") }
        .sheet(item: $model.composeRequest, onDismiss: { model.advanceComposeQueue() }) { request in
            ComposeAccountView(request: request).environmentObject(model)
        }
        .background(DarkWindowChrome())
        .task { model.start() }
    }
    private var navigation: some View {
        SidebarView(horizontal: model.placement.horizontal)
            .frame(width: model.placement.horizontal ? nil : 258, height: model.placement.horizontal ? 136 : nil)
            .environment(\.colorScheme, .dark)
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            if let account = model.selectedAccount {
                if (model.webMode || account.usesWeb) && !account.isDemo { webWorkspace(account) }
                else {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            MessageListView().frame(width: min(300, geometry.size.width * 0.43))
                            Divider()
                            MessageReaderView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else { emptyWorkspace }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
    }
    private var workspaceHeader: some View {
        VStack(spacing: 6) {
            if compactHeader {
                accountHeader
                HStack { Spacer(minLength: 0); headerActions }
            } else {
                HStack(spacing: 10) { accountHeader; Spacer(minLength: 0); headerActions }
            }
        }.padding(.horizontal, 23).frame(height: compactHeader ? 116 : 78)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .background(Palette.navigationBackground)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { compactHeader = geometry.size.width < 700 }
                    .onChange(of: geometry.size.width) { _, width in compactHeader = width < 700 }
            })
    }
    private var accountHeader: some View {
        HStack(spacing: 10) {
            if let account = model.selectedAccount {
                AccountPhoto(account: account, sessions: model.webSessions)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(account.email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !account.isDemo {
                    Button { model.webSessions.showCalendar(account: account) } label: {
                        HStack(spacing: 8) {
                            CalendarButtonIcon()
                            Text("Agenda").font(.system(size: 12, weight: .semibold))
                        }.padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).help("Ouvrir l’Agenda de ce compte")
                    Button {
                        if !NSWorkspace.shared.open(URL(string: "https://www.swisstransfer.com/fr")!) {
                            model.alert = "Impossible d’ouvrir SwissTransfer dans le navigateur."
                        }
                    } label: {
                        SwissTransferButtonIcon()
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .help("SwissTransfer · Envoyer de gros fichiers dans le navigateur")
                        .accessibilityLabel("Ouvrir SwissTransfer")
                    NextAppointmentTicker(account: account, sessions: model.webSessions).id(account.id)
                }
            } else { Text("Votre espace mail").font(.headline) }
        }
    }
    private var headerActions: some View {
        HStack(spacing: 10) {
            if model.selectedAccount?.usesWeb == true {
                Label("Gmail intégré", systemImage: "lock.rectangle").labelStyle(.iconOnly).font(.system(size: 11)).foregroundStyle(Palette.accent).help("Gmail intégré")
            } else if model.selectedAccount != nil {
                Menu {
                    Button("Lecture native") { model.webMode = false }
                    Button("Gmail web · expérimental") { model.webMode = true }
                } label: { Label(model.webMode ? "Gmail web" : "Lecture native", systemImage: "rectangle.split.3x1").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
            }
            Button { showPlacement.toggle() } label: {
                PlacementPreview(position: model.placement, selected: false).frame(width: 26, height: 20)
                    .padding(8).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help("Position de la barre de navigation")
                .accessibilityLabel("Position de la navigation")
                .popover(isPresented: $showPlacement) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Position de la navigation").font(.system(size: 13, weight: .semibold))
                        LazyVGrid(columns: [GridItem(.fixed(94)), GridItem(.fixed(94))], spacing: 10) {
                            ForEach(NavigationPlacement.allCases) { position in
                                Button {
                                    model.navigationPlacement = position.rawValue
                                    showPlacement = false
                                } label: {
                                    VStack(spacing: 7) {
                                        PlacementPreview(position: position, selected: model.placement == position).frame(width: 64, height: 42)
                                        Text(position.label).font(.system(size: 11, weight: .medium))
                                    }.frame(width: 94, height: 76)
                                        .background(model.placement == position ? Palette.accent.opacity(0.18) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel(position.label)
                                    .accessibilityAddTraits(model.placement == position ? .isSelected : [])
                            }
                        }
                    }.padding(18).background(Color(red: 0.07, green: 0.10, blue: 0.10)).environment(\.colorScheme, .dark)
                }
            Divider().frame(height: 23)
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Actualiser · ⌘R")
            Button { model.showSwitcher = true } label: {
                HStack(spacing: 7) { Image(systemName: "rectangle.on.rectangle"); Text("⌘ K").font(.system(size: 10, weight: .medium, design: .monospaced)) }
                .padding(.horizontal, 10).padding(.vertical, 7).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).help("Changer de compte")
        }.fixedSize()
    }
    private func webWorkspace(_ account: MailAccount) -> some View {
        IntegratedGmailView(account: account, sessions: model.webSessions, showNative: account.usesWeb ? nil : { model.webMode = false })
    }
    private var emptyWorkspace: some View {
        FirstAccountWelcome { model.showAdd = true }
    }

}

private struct NextAppointmentTicker: View {
    let account: MailAccount
    @ObservedObject var sessions: WebSessions
    var body: some View {
        let state = sessions.upcomingAppointments[account.id] ?? .loading
        Button { sessions.showCalendar(account: account, appointment: state.appointment) } label: {
            HStack(spacing: 7) {
                Circle().fill(state.appointment == nil ? .white.opacity(0.35) : Palette.accent).frame(width: 5, height: 5)
                AppointmentMarquee(text: state.message, moving: state.appointment != nil)
            }.padding(.horizontal, 9).frame(height: 36)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.accent.opacity(0.15), lineWidth: 1))
        }.buttonStyle(.plain).frame(minWidth: 90, idealWidth: 220, maxWidth: 360)
            .help(state.message + "\nCliquer pour ouvrir dans l’Agenda du compte.")
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { sessions.showCalendar(account: account, appointment: state.appointment) }
            .accessibilityLabel(state.message)
            .accessibilityHint("Ouvrir le rendez-vous dans l’Agenda du compte sélectionné")
            .task(id: account.id) {
                while !Task.isCancelled {
                    await sessions.refreshNextAppointment(account: account)
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                }
            }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct AppointmentMarquee: View {
    let text: String
    let moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var textWidth: CGFloat = 200
    @ViewState private var origin = Date()
    @ViewState<Date?> private var pausedAt: Date?
    var body: some View {
        GeometryReader { geometry in
            if reduceMotion || !moving {
                Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pausedAt != nil)) { context in
                    let elapsed = max(0, (pausedAt ?? context.date).timeIntervalSince(origin))
                    let distance = max(1, geometry.size.width + textWidth + 38)
                    let offset = geometry.size.width - (elapsed * 28).truncatingRemainder(dividingBy: distance)
                    Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .background(GeometryReader { measured in Color.clear.preference(key: MarqueeWidthKey.self, value: measured.size.width) })
                        .frame(height: geometry.size.height, alignment: .leading)
                        .offset(x: offset)
                }
            }
        }.clipped()
            .onPreferenceChange(MarqueeWidthKey.self) { if $0 > 0 { textWidth = $0 } }
            .onChange(of: text) { _, _ in origin = Date(); pausedAt = nil }
            .onHover { hovering in
                if hovering { if pausedAt == nil { pausedAt = Date() } }
                else if let pause = pausedAt { origin = origin.addingTimeInterval(Date().timeIntervalSince(pause)); pausedAt = nil }
            }
    }
}

private struct SwissTransferButtonIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.30), Color(red: 0.77, green: 0.07, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "arrow.up.doc.fill")
                .font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
        }.frame(width: 34, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .accessibilityHidden(true)
    }
}

private struct CalendarButtonIcon: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 11)
                    .background(LinearGradient(colors: [Color(red: 1, green: 0.36, blue: 0.30), .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(context.date.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [.white, Color(red: 0.87, green: 0.93, blue: 0.97)], startPoint: .top, endPoint: .bottom))
            }.frame(width: 34, height: 36).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        }.accessibilityHidden(true)
    }
}

private struct AccountPhoto: View {
    let account: MailAccount
    @ObservedObject var sessions: WebSessions
    var body: some View {
        Group {
            if let photo = sessions.accountPhotos[account.id] { Image(nsImage: photo).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.white.opacity(0.55)).padding(2) }
        }.frame(width: 34, height: 34).clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .accessibilityLabel("Photo du compte " + account.name)
    }
}

private struct PlacementPreview: View {
    let position: NavigationPlacement
    let selected: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: position == .left ? .leading : position == .right ? .trailing : position == .top ? .top : .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 2).fill(Palette.accent)
                    .frame(width: position.horizontal ? nil : geometry.size.width * 0.28,
                           height: position.horizontal ? geometry.size.height * 0.28 : nil)
                    .padding(3)
            }.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Palette.accent : .white.opacity(0.35), lineWidth: 1))
        }.accessibilityHidden(true)
    }
}

private struct DarkWindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.095, blue: 0.09, alpha: 1)
            window?.titlebarAppearsTransparent = true
        }
    }
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ view: NSView, context: Context) { }
}

private struct GmailExtraFolders: View {
    let account: MailAccount
    @ObservedObject var sessions: WebSessions
    @ViewState private var search = ""
    var body: some View {
        let discovered = sessions.mailboxes[account.id]?.navigationItems ?? []
        let defaults = [GmailNavigationItem(title: "En attente", fragment: "snoozed"),
                        GmailNavigationItem(title: "Brouillons", fragment: "drafts"),
                        GmailNavigationItem(title: "Programmés", fragment: "scheduled"),
                        GmailNavigationItem(title: "Tous les messages", fragment: "all"),
                        GmailNavigationItem(title: "Spam", fragment: "spam"),
                        GmailNavigationItem(title: "Importants", fragment: "imp")]
        let items = defaults.map { standard in discovered.first(where: { $0.fragment == standard.fragment }) ?? standard } + discovered.filter { extra in !defaults.contains(where: { $0.fragment == extra.fragment }) }
        VStack(alignment: .leading, spacing: 9) {
            Text("DOSSIERS ET LIBELLÉS").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
            TextField("Rechercher un libellé", text: $search).textFieldStyle(.plain).font(.system(size: 11))
                .padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                            Button { sessions.navigate(account: account, item: item) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.symbol).frame(width: 15).foregroundStyle(Palette.accent)
                                    Text(item.title).font(.system(size: 11)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(item.title).accessibilityLabel("Ouvrir " + item.title)
                        }
                    }
                }.frame(maxHeight: 185)
        }.foregroundStyle(.white.opacity(0.8)).id(account.id)
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var horizontal = false
    @ViewState<MailAccount?> private var renameTarget: MailAccount?
    @ViewState<MailAccount?> private var deleteTarget: MailAccount?
    var body: some View {
        Group {
            if horizontal { horizontalBar }
            else { verticalBar }
        }
            .sheet(item: $renameTarget) { account in
                RenameAccountView(account: account).environmentObject(model)
            }
            .alert("Supprimer ce compte d’Inboxy ?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Annuler", role: .cancel) { deleteTarget = nil }
                Button("Supprimer le compte", role: .destructive) {
                    guard let account = deleteTarget else { return }
                    deleteTarget = nil
                    Task { await model.remove(account) }
                }
            } message: {
                if let account = deleteTarget {
                    Text("Le compte \(account.email) et sa session locale seront retirés d’Inboxy. Vos messages et votre compte Google ne seront pas supprimés." + (account.usesWeb ? "" : " L’autorisation API Google sera également révoquée."))
                }
            }
    }
    private var gmailNavigationButton: some View {
        Button { model.toggleGmailNavigation() } label: {
            Image(systemName: model.gmailFoldersExpanded ? "minus" : "plus")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                .frame(width: 26, height: 26)
                .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(!model.usingWeb)
            .help(model.gmailFoldersExpanded ? "Replier les dossiers et libellés" : "Afficher les dossiers et libellés sous Corbeille")
            .accessibilityLabel(model.gmailFoldersExpanded ? "Replier les dossiers et libellés" : "Afficher les dossiers et libellés sous Corbeille")
            .popover(isPresented: Binding(get: { horizontal && model.gmailFoldersExpanded }, set: { if horizontal { model.gmailFoldersExpanded = $0 } })) {
                extraGmailFolders.frame(width: 280).padding(12).background(Palette.navigationBackground).environment(\.colorScheme, .dark)
            }
    }
    @ViewBuilder private var extraGmailFolders: some View {
        if let account = model.selectedAccount {
            GmailExtraFolders(account: account, sessions: model.webSessions).id(account.id)
        }
    }
    private var verticalBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Inboxy").font(.system(size: 30, weight: .light, design: .rounded)).tracking(1)
                Text("✦").font(.system(size: 18)).foregroundStyle(Palette.accent)
                Spacer()
                Text("LA BOITE À GMAIL").font(.system(size: 7, weight: .medium)).tracking(0.8).foregroundStyle(.white.opacity(0.6)).fixedSize()
            }.padding(.top, 39).padding(.horizontal, 23).padding(.bottom, 25)
            Button { model.openGmail(compose: true) } label: {
                HStack { Image(systemName: "square.and.pencil"); Text("Nouveau message").font(.system(size: 12, weight: .semibold)); Spacer(); Text("⌘N").font(.system(size: 10)).opacity(0.65) }
                    .padding(13).background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 23)
            ResizableSidebarPanels(
                folders: AnyView(ScrollView { VStack(alignment: .leading, spacing: 0) {
                    ForEach(MailFolder.allCases) { folder in
                        Button { model.openFolder(folder) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: folder.symbol).frame(width: 18)
                                Text(folder.rawValue).font(.system(size: 12, weight: model.folderSelected(folder) ? .semibold : .regular))
                                Spacer()
                                if folder == .inbox { Text(model.selectedInboxCount.map(String.init) ?? "—").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6)) }
                            }.foregroundStyle(model.folderSelected(folder) ? .white : .white.opacity(0.57))
                                .padding(.horizontal, 13).padding(.vertical, 10)
                                .background(model.folderSelected(folder) ? .white.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .overlay(alignment: .trailing) {
                                if folder == .trash { gmailNavigationButton.padding(.trailing, 7) }
                            }
                            .padding(.horizontal, 16)
                    }
                    if model.gmailFoldersExpanded && model.usingWeb {
                        extraGmailFolders.padding(.horizontal, 18).padding(.top, 8)
                    }
                }.padding(.bottom, 6) }.environmentObject(model).environment(\.colorScheme, .dark)),
                work: AnyView(VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("VOS COMPTES").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.45))
                        Text("\(model.visibleAccounts.count)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.accent).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.accent.opacity(0.13), in: Capsule())
                        Spacer()
                        Button { model.showAdd = true } label: { Image(systemName: "plus").font(.system(size: 13)) }.buttonStyle(.plain).help("Ajouter un compte · ⌘⇧N")
                    }.padding(.horizontal, 24).padding(.bottom, 14)
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10))
                        TextField("Rechercher un compte", text: $model.accountSearch).textFieldStyle(.plain).font(.system(size: 11))
                    }.foregroundStyle(.white.opacity(0.5)).padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 20)
                    accountGroup("Travail")
                }.environmentObject(model).environment(\.colorScheme, .dark)),
                personal: AnyView(accountGroup("Personnel").environmentObject(model).environment(\.colorScheme, .dark))
            )
            VStack(spacing: 12) {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                HStack {
                    Menu {
                        Button("Automatique") { model.appearance = "system" }
                        Button("Clair") { model.appearance = "light" }
                        Button("Sombre") { model.appearance = "dark" }
                    } label: { Image(systemName: model.appearance == "light" ? "sun.max" : "moon.stars") }.menuStyle(.borderlessButton).frame(width: 27).help("Apparence")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.accounts.isEmpty ? "Aucun compte connecté" : model.checkingBadges.isEmpty ? "Relevé chaque minute" : "Vérification des comptes…").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        ProgramVersionStatus(version: model.programVersion, state: model.updateState) { model.openProgramVersion() }
                    }
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape").font(.system(size: 13)) }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 23).padding(.bottom, 18)
        }.background(Palette.navigationBackground)
    }
    private func accountGroup(_ group: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.uppercased()).font(.system(size: 8, weight: .medium)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.4)).padding(.leading, 26).padding(.top, 10).padding(.bottom, 7)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.filteredAccounts.filter { $0.group == group }) { account in accountRow(account) }
                }.padding(.horizontal, 13).padding(.bottom, 10)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var horizontalBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inboxy ✦").font(.system(size: 18, weight: .medium, design: .rounded))
                    Text("LA BOITE À GMAIL").font(.system(size: 7, weight: .medium)).tracking(0.8).foregroundStyle(.white.opacity(0.6))
                }
                ForEach(MailFolder.allCases) { folder in
                    Button { model.openFolder(folder) } label: {
                        Image(systemName: folder.symbol).frame(width: 28, height: 26)
                            .background(model.folderSelected(folder) ? Palette.accent.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help(folder.rawValue).accessibilityLabel(folder.rawValue)
                    if folder == .trash { gmailNavigationButton }
                }
                Spacer(minLength: 0)
                Button { model.openGmail(compose: true) } label: { Label("Nouveau message", systemImage: "square.and.pencil").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent)
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                TextField("Rechercher un compte", text: $model.accountSearch).textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 155)
                Button { model.showAdd = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Ajouter un compte")
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.filteredAccounts) { account in accountRow(account).frame(width: 200) }
                    }
                }.scrollIndicators(.visible)
            }
            HStack {
                Spacer()
                ProgramVersionStatus(version: model.programVersion, state: model.updateState) { model.openProgramVersion() }
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background(Palette.navigationBackground)
    }
    @ViewBuilder private func accountActions(_ account: MailAccount) -> some View {
        Button { renameTarget = account } label: { Label("Renommer…", systemImage: "pencil") }
        if !account.isDemo && !account.usesWeb {
            Button(account.notifications ? "Couper les notifications" : "Activer les notifications") {
                var changed = account; changed.notifications.toggle(); model.update(changed)
            }
        }
        Divider()
        Button(role: .destructive) { deleteTarget = account } label: { Label("Supprimer le compte…", systemImage: "trash") }
    }
    private func accountRow(_ account: MailAccount) -> some View {
        HStack(spacing: 5) {
            Button { model.select(account) } label: {
                HStack(spacing: 10) {
                    UnreadAccountBadge(count: model.unread[account.id], checking: model.checkingBadges.contains(account.id))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(account.email).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if model.removing.contains(account.id) { ProgressView().controlSize(.mini) }
                    else if model.errors[account.id] != nil || model.badgeErrors[account.id] != nil { Image(systemName: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(model.badgeHelp(account))
                .overlay(AccountDragSurface(account: account, horizontal: horizontal, select: { model.select(account) }, move: { id, after in
                    model.moveAccount(id, relativeTo: account.id, after: after)
                }))
            Menu { accountActions(account) } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options du compte \(account.name)")
                .help("Renommer ou supprimer ce compte")
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(model.selectedID == account.id ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.selectedID == account.id ? Palette.accent.opacity(0.25) : .clear, lineWidth: 0.5))
            .contentShape(Rectangle())
            .contextMenu { accountActions(account) }
            .disabled(model.removing.contains(account.id))
    }
}

private struct UnreadAccountBadge: View {
    let count: Int?
    let checking: Bool
    var body: some View {
        ZStack {
            Circle().fill((count ?? 0) > 0 ? Color(red: 0.9, green: 0.2, blue: 0.25) : .white.opacity(0.08))
            if count == nil && checking { ProgressView().controlSize(.mini) }
            else {
                Text(count.map(String.init) ?? "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45).padding(.horizontal, 3)
                    .foregroundStyle((count ?? 0) > 0 ? .white : .white.opacity(0.5))
            }
        }.frame(width: 29, height: 29)
            .accessibilityLabel(count.map { "\($0) messages non lus" } ?? "Non lus en attente")
    }
}

// AppKit owns the pointer sequence so clicking and dragging a sidebar button
// remain distinct, including when a WebKit view has keyboard focus.
private struct AccountDragSurface: NSViewRepresentable {
    let account: MailAccount
    let horizontal: Bool
    let select: () -> Void
    let move: (UUID, Bool) -> Void
    func makeNSView(context: Context) -> AccountDragView { AccountDragView() }
    func updateNSView(_ view: AccountDragView, context: Context) {
        view.horizontal = horizontal
        view.accountID = account.id
        view.accountName = account.name
        view.selectAccount = select
        view.moveAccount = move
    }
}

private final class AccountDragView: NSView, NSDraggingSource {
    private static let pasteboardType = NSPasteboard.PasteboardType("com.aeris.account-order")
    var horizontal = false
    var accountID = UUID()
    var accountName = ""
    var selectAccount: (() -> Void)?
    var moveAccount: ((UUID, Bool) -> Void)?
    private var insertionAfter: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.pasteboardType])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { selectAccount?() }
                return
            }
            let point = convert(next.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { continue }
            let item = NSPasteboardItem()
            item.setString(accountID.uuidString, forType: Self.pasteboardType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let preview = NSImage(size: bounds.size)
            preview.lockFocus()
            NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.15, alpha: 0.96).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            (accountName as NSString).draw(in: bounds.insetBy(dx: 12, dy: 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            preview.unlockFocus()
            dragging.setDraggingFrame(bounds, contents: preview)
            beginDraggingSession(with: [dragging], event: next, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    private func sourceID(_ sender: NSDraggingInfo) -> UUID? {
        guard sender.draggingSource is AccountDragView,
              let value = sender.draggingPasteboard.string(forType: Self.pasteboardType),
              let id = UUID(uuidString: value), id != accountID else { return nil }
        return id
    }
    private func isAfter(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        return horizontal ? point.x >= bounds.midX : point.y >= bounds.midY
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sourceID(sender) != nil else { return [] }
        insertionAfter = isAfter(sender)
        needsDisplay = true
        if let event = NSApp.currentEvent { autoscroll(with: event) }
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearInsertion() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearInsertion() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { sourceID(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearInsertion() }
        guard let id = sourceID(sender) else { return false }
        moveAccount?(id, isAfter(sender))
        return true
    }
    private func clearInsertion() { insertionAfter = nil; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let after = insertionAfter else { return }
        NSColor(calibratedRed: 0.18, green: 0.64, blue: 0.53, alpha: 1).setFill()
        NSBezierPath(roundedRect: (horizontal ? NSRect(x: after ? bounds.maxX - 2 : 0, y: 0, width: 2, height: bounds.height) : NSRect(x: 0, y: after ? bounds.maxY - 2 : 0, width: bounds.width, height: 2)), xRadius: 1, yRadius: 1).fill()
    }
}

private struct RenameAccountView: View {
    let account: MailAccount
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Renommer le compte", systemImage: "pencil").font(.system(size: 22, weight: .light))
            Text(account.email).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Nom affiché dans Inboxy", text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit { save() }
            Text("Ce nom s’affiche uniquement dans Inboxy. Votre adresse e-mail reste identique.").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 420).tint(Palette.accent)
            .onAppear { name = account.name; focused = true }
    }
    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if model.rename(account, to: name) { dismiss() }
    }
}

struct MessageListView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.folder.rawValue).font(.system(size: 21, weight: .semibold)).tracking(-0.6)
                    Spacer()
                    if model.loading { ProgressView().controlSize(.mini) }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Rechercher dans Gmail ↵", text: $model.search)
                        .textFieldStyle(.plain).font(.system(size: 12)).onSubmit { model.load() }
                    if !model.search.isEmpty { Button { model.search = ""; model.load() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text("MESSAGES · LECTURE SEULE").font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.messages.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }.padding(.horizontal, 23).padding(.top, 25).padding(.bottom, 17)
            if let id = model.selectedID, let error = model.errors[id] {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connexion à vérifier", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .semibold))
                    Text(error).font(.system(size: 11))
                    Button("Réessayer") { model.refresh() }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1))
            }
            if model.messages.isEmpty && !model.loading {
                VStack(spacing: 12) { Image(systemName: "tray").font(.system(size: 30, weight: .ultraLight)); Text("Aucun message à afficher").font(.system(size: 12)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.messages) { message in
                            Button { model.selectedMessageID = message.id; model.loadBody() } label: { MessageRow(message: message, selected: model.selectedMessageID == message.id) }.buttonStyle(.plain)
                        }
                        if model.nextPage != nil { Button("Charger les suivants") { model.load(more: true) }.disabled(model.loading).padding(15) }
                    }.padding(.horizontal, 10).padding(.bottom, 20)
                }
            }
            HStack(spacing: 6) { Circle().fill(Palette.accent).frame(width: 4, height: 4); Text("Relevé des comptes chaque minute").font(.system(size: 9)).foregroundStyle(.secondary); Spacer() }.padding(16)
        }.background(Color.surface.opacity(0.45))
    }
}

struct MessageRow: View {
    let message: MailMessage
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Circle().fill(message.unread ? Palette.accent : .clear).frame(width: 5, height: 5)
                Text(message.sender).font(.system(size: 12, weight: message.unread ? .semibold : .regular)).lineLimit(1)
                Spacer()
                Text(message.date, style: .time).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(message.subject).font(.system(size: 12, weight: .medium)).lineLimit(1).padding(.leading, 13)
            HStack(alignment: .bottom) {
                Text(message.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(3)
                if message.starred { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(red: 0.76, green: 0.61, blue: 0.35)) }
            }.padding(.leading, 13)
        }.padding(.horizontal, 13).padding(.vertical, 17).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) { if selected { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 2, height: 37) } }
    }
}

struct MessageReaderView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let message = model.selectedMessage {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("LECTURE SEULE", systemImage: "envelope.open").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.body, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copier le texte")
                    Button { model.openGmail() } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).padding(.leading, 12).help("Ouvrir dans Gmail")
                }.padding(.horizontal, 34).frame(height: 63)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 6) { Text(model.selectedAccount?.name.uppercased() ?? "").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.accent).padding(.horizontal, 9).padding(.vertical, 6).background(Palette.accent.opacity(0.08), in: Capsule()); Spacer() }
                        Text(message.subject).font(.system(size: 29, weight: .medium)).tracking(-0.7).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        HStack(alignment: .center, spacing: 12) {
                            Avatar(name: message.sender, color: Palette.accent, size: 39)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.sender).font(.system(size: 12, weight: .semibold))
                                Text(message.senderEmail).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Text(message.date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Divider()
                        if model.loadingBody { ProgressView("Chargement du message…").font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 160) }
                        else { Text(message.body).font(.system(size: 13)).lineSpacing(8).foregroundStyle(.primary.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        HStack {
                            Button { model.openGmail() } label: { Label("Répondre dans Gmail", systemImage: "arrowshape.turn.up.left").font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.bordered)
                            Spacer()
                        }.padding(.top, 8)
                    }.padding(34)
                }
            }.background(Color.canvas)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "sun.horizon").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(Palette.accent.opacity(0.65))
                Text("Un peu d’espace pour l’essentiel.").font(.system(size: 22, weight: .light))
                Text("Sélectionnez un message pour le lire.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Avatar: View {
    let name: String
    let color: Color
    let size: CGFloat
    var body: some View {
        Text(String(name.split(separator: " ").prefix(2).compactMap(\.first))).font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
            .foregroundStyle(color).frame(width: size, height: size).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}


private struct ComposeAccountView: View {
    let request: MailComposeRequest
    @EnvironmentObject var model: AppModel
    @ViewState<String> private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Envoyer avec Inboxy", systemImage: "paperplane").font(.system(size: 23, weight: .light))
            Text("Choisissez le compte Gmail expéditeur.").font(.system(size: 13)).foregroundStyle(.secondary)
            if !request.files.isEmpty {
                Text(request.files.map(\.lastPathComponent).joined(separator: "\n"))
                    .font(.system(size: 12)).lineLimit(4).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            if !request.to.isEmpty { Text("Destinataire : \(request.to)").font(.system(size: 12)).lineLimit(2) }
            if !request.subject.isEmpty { Text("Objet : \(request.subject)").font(.system(size: 12)).lineLimit(2) }
            TextField("Rechercher un compte", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.accounts.filter { query.isEmpty || ($0.name + $0.email).localizedCaseInsensitiveContains(query) }) { account in
                        Button { model.compose(request, from: account) } label: {
                            HStack(spacing: 12) {
                                Avatar(name: account.name, color: account.color, size: 30)
                                VStack(alignment: .leading, spacing: 3) { Text(account.name).font(.system(size: 13, weight: .medium)); Text(account.email).font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.removing.contains(account.id))
                    }
                }
            }.frame(height: 250)
            if model.accounts.isEmpty { Text("Ajoutez d’abord un compte Gmail depuis +, puis relancez l’envoi depuis le Finder.").font(.caption).foregroundStyle(.secondary) }
            Text(request.files.isEmpty ? "Le message s’ouvre en brouillon dans Gmail. Aucun envoi automatique." : "Les fichiers seront joints au compte choisi lorsque vous cliquerez sur « Joindre les fichiers » ou sur le trombone de Gmail. Aucun envoi automatique.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Annuler") { model.composeRequest = nil }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 490).tint(Palette.accent)
    }
}

struct ProgramVersionStatus: View {
    let version: String
    let state: AppUpdateState
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.offer == nil || reduceMotion)) { context in
            let phase = reduceMotion ? 1 : (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.8) + 1) / 2
            let color = state.offer == nil ? Color.white.opacity(0.55) : Color(red: 0.30 + 0.70 * phase, green: 0.83 - 0.08 * phase, blue: 0.72 - 0.42 * phase)
            Button(action: action) {
                HStack(spacing: 4) {
                    if state.offer != nil { Image(systemName: "arrow.down.circle.fill") }
                    Text(state.label(version: version)).lineLimit(2).multilineTextAlignment(.leading)
                }.font(.system(size: 9, weight: state.offer == nil ? .regular : .semibold))
                    .foregroundStyle(color).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(state == .checking)
                .help(state.offer == nil ? "Vérifier les nouvelles versions sur GitHub" : "Ouvrir la page de téléchargement de la nouvelle version")
                .accessibilityLabel("Inboxy, " + state.label(version: version))
                .accessibilityHint(state.offer == nil ? "Vérifie les mises à jour" : "Ouvre la nouvelle version dans le navigateur")
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct FirstAccountWelcome: View {
    let connect: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56, weight: .ultraLight)).foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Bienvenue dans Inboxy").font(.system(size: 28, weight: .light, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Connectez votre premier compte Gmail")
                .font(.system(size: 17, weight: .medium)).multilineTextAlignment(.center)
            Text("Retrouvez vos messages ici, puis ajoutez vos autres comptes quand vous le souhaitez.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: connect) {
                Label("Connecter mon premier compte Gmail", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("La connexion s’effectue sur la page Google dans Inboxy.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResizableSidebarPanels: NSViewRepresentable {
    var folders: AnyView
    var work: AnyView
    var personal: AnyView
    func makeNSView(context: Context) -> SidebarPanelSplit {
        let split = SidebarPanelSplit()
        for view in [folders, work, personal] {
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            split.addSubview(hosting)
        }
        return split
    }
    func updateNSView(_ split: SidebarPanelSplit, context: Context) {
        for (index, view) in [folders, work, personal].enumerated() {
            (split.subviews[index] as? NSHostingView<AnyView>)?.rootView = view
        }
    }
}
private final class SidebarPanelSplit: NSSplitView, NSSplitViewDelegate {
    private var weights = SidebarPanelLayout.validWeights(UserDefaults.standard.array(forKey: "sidebarPanelWeights") as? [Double] ?? SidebarPanelLayout.defaults)
    override var isFlipped: Bool { true }
    override var dividerThickness: CGFloat { 8 }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isVertical = false; dividerStyle = .thin; delegate = self
        setAccessibilityLabel("Dossiers Gmail, Travail et Personnel : panneaux redimensionnables")
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) n’est pas utilisé") }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard subviews.count == 3 else { return }
        let sizes = SidebarPanelLayout.sizes(available: Double(max(0, bounds.height - dividerThickness * 2)), weights: weights)
        var y: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: CGFloat(sizes[index]))
            y += CGFloat(sizes[index]) + dividerThickness
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            weights = SidebarPanelLayout.defaults
            resizeSubviews(withOldSize: bounds.size)
        } else {
            super.mouseDown(with: event)
            let total = subviews.reduce(CGFloat(0)) { $0 + $1.frame.height }
            if total > 0 { weights = SidebarPanelLayout.validWeights(subviews.map { Double($0.frame.height / total) }) }
        }
        UserDefaults.standard.set(weights, forKey: "sidebarPanelWeights")
    }
    override func drawDivider(in rect: NSRect) {
        NSColor(srgbRed: 0.055, green: 0.095, blue: 0.09, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0.35, green: 0.65, blue: 0.58, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 18, y: rect.midY - 1.5, width: 36, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex >= 0 && dividerIndex < 2 else { return proposedPosition }
        let low = subviews[dividerIndex].frame.minY + CGFloat(SidebarPanelLayout.minima[dividerIndex])
        let high = subviews[dividerIndex + 1].frame.maxY - CGFloat(SidebarPanelLayout.minima[dividerIndex + 1]) - dividerThickness
        return high >= low ? min(max(proposedPosition, low), high) : proposedPosition
    }
}
