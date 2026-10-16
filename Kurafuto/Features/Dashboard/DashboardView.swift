import SwiftUI

/// The Servers tab: the active panel, crash warnings first, one tab per server, and for the selected server
/// its last hour of CPU and RAM, players, controls and latest console lines. Data lives in `DashboardModel`.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = DashboardModel()
    @SceneStorage("dashboard.selectedServer") private var storedSelection = ""
    @State private var path = NavigationPath()
    @State private var showCreate = false
    @State private var confirm: ConfirmAction?

    var body: some View {
        NavigationStack(path: $path) {
            LoadableView(state: model.servers, retry: model.load) { servers in
                ScrollView {
                    VStack(spacing: 16) {
                        DashboardHeader(problem: model.liveProblem, onCreate: app.canCreateServers ? { showCreate = true } : nil)
                            .entrance(0)
                        if let problem = model.liveProblem { StaleValuesBanner(problem: problem) }
                        ForEach(model.crashed) { server in
                            NavigationLink(value: DashboardRoute.detail(server)) { CrashBanner(server: server) }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                        }
                        if servers.isEmpty {
                            emptyState.entrance(1)
                        } else {
                            ServerTabBar(servers: servers, stats: model.stats, selection: $model.selectedID)
                                .entrance(1)
                            if let server = model.selected {
                                selectedServer(server)
                                    .id(server.id)
                                    .transition(.opacity)
                                    .entrance(2)
                            }
                            summary(servers).entrance(3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .animation(reduceMotion ? nil : .snappy, value: model.selectedID)
                    .animation(reduceMotion ? nil : .snappy, value: model.crashed.map(\.id))
                }
                .refreshable { await model.load() }
            }
            .themedBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle(app.activeInstance?.name ?? String(localized: "Servers"))
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .detail(let server): ServerDetailView(server: server)
                case .console(let server): ConsoleView(server: server)
                case .players(let server): PlayersView(server: server)
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await model.load() } }) { CreateServerView() }
            .destructiveConfirmation($confirm)
            .errorAlert($model.actionError)
            .eulaPrompt(for: $model.eulaServer) { await model.load() }
            .task(id: ObjectIdentifier(app.service)) {
                if model.selectedID == nil, !storedSelection.isEmpty { model.selectedID = storedSelection }
                await model.run(with: app.service)
            }
            .onChange(of: model.selectedID) { _, id in
                storedSelection = id ?? ""
                Task { await model.selectionChanged() }
            }
            .onChange(of: model.lastRefresh) {
                publishWidgets()
                openRequestedServer()
            }
            .onChange(of: app.requestedServer) { openRequestedServer() }
            // Lets Siri recognise server names in "Start <server> in Kurafuto".
            .onChange(of: model.servers.value?.map(\.serverName)) { KurafutoShortcuts.updateAppShortcutParameters() }
        }
    }

    private func selectedServer(_ server: Server) -> some View {
        let stats = model.stats[server.id]
        return VStack(spacing: 16) {
            ServerOverviewCard(server: server, stats: stats, history: model.history[server.id] ?? [])
                .contextMenu { moreActions(server) }
            PlayersCard(server: server, stats: stats)
            ServerActionBar(server: server, status: stats?.status ?? .offline,
                            busy: model.isBusy(server) ? model.busy?.action : nil) { action in
                request(action, on: server)
            }
            if stats?.running == true, let lines = model.consoleTail[server.id], !lines.isEmpty {
                ConsolePreviewCard(server: server, lines: lines)
            }
        }
    }

    private func summary(_ servers: [Server]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
            HStack(spacing: 4) {
                Text("\(model.onlineCount)/\(servers.count) online")
                Text(verbatim: "·")
                Text("\(model.playerCount) players")
            }
            .contentTransition(.numericText())
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text(app.canCreateServers ? "Create your first server on this panel."
                                      : "No server on this panel is shared with your account.")
        } actions: {
            if app.canCreateServers {
                Button("Create Server") { showCreate = true }
                    .buttonStyle(InstrumentButtonStyle()).frame(width: 180)
            }
        }
    }

    // MARK: Widgets

    private func publishWidgets() {
        guard let servers = model.servers.value, let panel = app.activeInstance else { return }
        let look = Appearance.shared
        WidgetSync.publish(WidgetSync.snapshot(panelName: panel.name, servers: servers, stats: model.stats,
                                               history: model.history, backups: model.lastBackups,
                                               isPrivate: app.lock.isEnabled, mode: look.mode,
                                               accent: look.preset(for: .accent)))
    }

    /// Only a server this panel lists is shown; a link to anything else is dropped.
    private func openRequestedServer() {
        guard let target = app.requestedServer, let servers = model.servers.value else { return }
        app.requestedServer = nil
        guard let server = servers.first(where: { $0.id == target.serverID }) else { return }
        model.selectedID = server.id
        path = NavigationPath()
        switch target.screen {
        case .console: path.append(DashboardRoute.console(server))
        case .details: path.append(DashboardRoute.detail(server))
        case nil: break
        }
    }

    // MARK: Actions

    @ViewBuilder private func moreActions(_ server: Server) -> some View {
        ForEach([ServerAction.start, .restart, .stop, .backup, .kill], id: \.self) { action in
            Button(role: action.isDestructive ? .destructive : nil) { request(action, on: server) } label: {
                Label(action.label, systemImage: action.symbol)
            }
        }
    }

    /// Stop and kill ask first (and need Face ID when the app lock is on).
    private func request(_ action: ServerAction, on server: Server) {
        if action.isDestructive {
            confirm = ConfirmAction(title: action == .kill ? String(localized: "Force kill \(server.serverName)?")
                                                           : String(localized: "Stop \(server.serverName)?"),
                                    message: String(localized: "Connected players will be disconnected."),
                                    buttonLabel: action.label) { await model.perform(action, on: server) }
        } else {
            Task {
                if await model.perform(action, on: server) { app.followInLiveActivity(action, on: server) }
            }
        }
    }
}

#Preview { DashboardView().environment(AppState.preview) }
