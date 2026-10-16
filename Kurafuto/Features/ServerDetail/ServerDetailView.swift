import SwiftUI
import Charts

/// Server detail page – mirrors the tabs in the Crafty panel:
/// Overview · Console · Logs · Schedules · Backups · Files · Players · Webhooks · Config
struct ServerDetailView: View {
    @Environment(AppState.self) private var app
    @State var server: Server
    @State private var stats: ServerStats?
    @State private var history: [StatPoint] = []
    @State private var busyAction: ServerAction?
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?
    @State private var liveProblem: PanelProblem?
    @State private var eulaServer: Server?
    /// Start, restart and stop symbols differ in height; a shared box keeps the three buttons level.
    @ScaledMetric(relativeTo: .title3) private var actionIconHeight: CGFloat = 26

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header.entrance(0)
                if let liveProblem { StaleValuesBanner(problem: liveProblem) }
                controls.entrance(1)
                if let s = stats, s.running { live(s).entrance(2) }
                manage.entrance(3)
                connection.entrance(4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationTitle(server.serverName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { Task { await run(.backup) } } label: { Label("Back Up Now", systemImage: ServerAction.backup.symbol) }
                Button { Task { await run(.updateExecutable) } } label: { Label("Update JAR", systemImage: ServerAction.updateExecutable.symbol) }
                if app.canCreateServers {
                    Button { Task { await run(.clone) } } label: { Label("Clone", systemImage: ServerAction.clone.symbol) }
                }
                Divider()
                Button(role: .destructive) {
                    confirm = ConfirmAction(title: String(localized: "Kill process?"),
                                            message: String(localized: "Kill stops the server immediately without saving."),
                                            buttonLabel: String(localized: "Kill")) { await run(.kill) }
                } label: { Label("Kill", systemImage: ServerAction.kill.symbol) }
            } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("More actions")
        }
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .eulaPrompt(for: $eulaServer) { await refresh() }
        .task { await poll() }
        .refreshable { await refresh() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ServerIcon(base64: stats?.icon, type: server.type)
            VStack(alignment: .leading, spacing: 4) {
                StatusBadge(status: stats?.status ?? .offline)
                Text(stats?.desc?.strippingMinecraftFormatting ?? server.type.label)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(verbatim: "\(stats?.version ?? server.type.label) · :\(server.serverPort)")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if let s = stats { PlayerCount(online: s.online, max: s.max, large: true) }
        }
        .card(padding: 18)
    }

    private var controls: some View {
        let running = stats?.running == true
        return HStack(spacing: 10) {
            actionButton(.start, enabled: !running, color: Theme.accent)
            actionButton(.restart, enabled: running, color: Theme.warning)
            actionButton(.stop, enabled: running, color: Theme.danger)
        }
    }

    private func actionButton(_ a: ServerAction, enabled: Bool, color: Color) -> some View {
        Button {
            if a == .stop {
                confirm = ConfirmAction(title: String(localized: "Stop server?"),
                                        message: String(localized: "\(stats?.online ?? 0) players will be disconnected."),
                                        buttonLabel: String(localized: "Stop")) { await run(a) }
            } else { Task { await run(a) } }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if busyAction == a { ProgressView().tint(color) } else { Image(systemName: a.symbol).font(.title3) }
                }
                .frame(height: actionIconHeight)
                Text(a.label).font(.caption.weight(.semibold))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(InstrumentButtonStyle(kind: .tinted, color: color))
        .disabled(!enabled || busyAction != nil)
    }

    private func live(_ s: ServerStats) -> some View {
        VStack(spacing: 10) {
            SectionLabel("Live")
            HStack(spacing: 10) {
                GaugeTile(title: "CPU", value: s.cpu, color: Theme.cpu, delay: 0.2)
                GaugeTile(title: "RAM", value: s.memPercent, color: Theme.ram, caption: s.mem, delay: 0.3)
                ValueTile(title: "World", value: s.worldSize ?? "–", color: Theme.storage)
            }
            .fixedSize(horizontal: false, vertical: true)
            if history.count > 2 { chart.card() }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend("CPU", Theme.cpu)
                legend("RAM", Theme.ram)
                Spacer()
                Text("live").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
            }
            Chart(history) { p in
                AreaMark(x: .value("Time", p.date), y: .value("CPU", p.cpu), series: .value("Metric", "CPU"))
                    .foregroundStyle(LinearGradient(colors: [Theme.cpu.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.date), y: .value("CPU", p.cpu), series: .value("Metric", "CPU"))
                    .foregroundStyle(Theme.cpu)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.date), y: .value("RAM", p.mem), series: .value("Metric", "RAM"))
                    .foregroundStyle(Theme.ram)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel().font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 130)
            .animation(.snappy, value: history.count)
            .accessibilityLabel("CPU and RAM over time")
        }
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(title).font(.mono(.caption2, weight: .medium))
        }
    }

    private var manage: some View {
        VStack(spacing: 10) {
            SectionLabel("Manage")
            VStack(spacing: 0) {
                nav("Console", "terminal.fill", Theme.accent) { ConsoleView(server: server) }
                nav("Logs", "doc.text.magnifyingglass", Theme.accent) { LogsView(server: server) }
                nav("Players", "person.2.fill", Theme.players, badge: stats?.online) { PlayersView(server: server) }
                nav("Schedules", "calendar.badge.clock", Theme.accent) { SchedulesView(server: server) }
                nav("Backups", "externaldrive.fill", Theme.storage) { BackupsView(server: server) }
                nav("Files", "folder.fill", Theme.storage) { FileBrowserView(server: server, path: "") }
                nav("server.properties", "slider.horizontal.3", Theme.accent) { PropertiesEditorView(server: server) }
                nav("Webhooks", "bell.badge.fill", Theme.accent) { WebhooksView(server: server) }
                nav("Configuration", "gearshape.2.fill", Theme.secondaryText, last: true) { ServerSettingsView(server: $server) }
            }
            .card(padding: 0)
        }
    }

    private var connection: some View {
        VStack(spacing: 10) {
            SectionLabel("Connection")
            VStack(spacing: 12) {
                detail("Address") {
                    Text(verbatim: "\(app.activeInstance?.baseURL.host() ?? server.serverIP):\(server.serverPort)")
                        .textSelection(.enabled)
                }
                if let world = stats?.worldName { detail("World") { Text(world) } }
                if let size = stats?.worldSize { detail("World size") { Text(size) } }
                if let started = stats?.started {
                    detail("Started") {
                        Text(ServerStats.startTime(started)?.formatted(date: .abbreviated, time: .shortened) ?? started)
                    }
                }
            }
            .card()
        }
    }

    private func detail<V: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondaryText)
            Spacer()
            value().font(.mono(.footnote))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func nav<D: View>(_ title: LocalizedStringKey, _ symbol: String, _ color: Color, badge: Int? = nil, last: Bool = false,
                              @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 32)
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let badge, badge > 0 {
                    Text(verbatim: "\(badge)").font(.mono(.caption, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.players.opacity(0.16), in: Capsule())
                        .foregroundStyle(Theme.players)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 56) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private func refresh() async {
        let s: ServerStats
        do { s = try await app.service.stats(serverID: server.id) }
        catch { liveProblem = error.panelProblem; return }
        liveProblem = nil
        stats = s
        history.append(StatPoint(date: .now, cpu: s.cpu, mem: s.memPercent))
        if history.count > 60 { history.removeFirst() }
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(stats?.status == .starting ? 1 : 3))
        }
    }

    private func run(_ action: ServerAction) async {
        busyAction = action
        defer { busyAction = nil }
        do {
            try await app.service.send(action, serverID: server.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.followInLiveActivity(action, on: server)
        } catch CraftyError.eulaRequired {
            eulaServer = server
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = error
        }
        await refresh()
    }
}

struct StatPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let mem: Double
}

extension String {
    /// Crafty HTML-escapes log lines (Python `html.escape`) unless ANSI stripping is also turned off.
    /// The app shows logs as plain text, so the five entities are turned back into characters.
    var unescapingCraftyLogHTML: String {
        replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Strips Minecraft formatting codes (§a, §l, …) from MOTDs.
    /// Important: NEVER render MOTDs as HTML (known stored-XSS issue in the web panel, issue #647).
    var strippingMinecraftFormatting: String {
        replacingOccurrences(of: "§[0-9a-fk-or]", with: "", options: .regularExpression)
    }
}

#Preview {
    NavigationStack { ServerDetailView(server: MockData.servers[0]) }.environment(AppState.preview)
}
