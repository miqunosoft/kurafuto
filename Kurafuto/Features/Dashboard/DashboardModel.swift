import Foundation
import UIKit

/// State of the Servers tab: the panel's servers, their live stats, the selected server's last hour
/// and console tail. Views only read it and call its actions.
@Observable
@MainActor
final class DashboardModel {
    private(set) var servers: Loadable<[Server]> = .idle
    private(set) var stats: [String: ServerStats] = [:]
    /// CPU/RAM of the last hour per server, filled for servers that were selected.
    private(set) var history: [String: [StatSample]] = [:]
    private(set) var consoleTail: [String: [String]] = [:]
    /// Set when no server's stats could be loaded, so the values on screen are stale.
    private(set) var liveProblem: PanelProblem?
    /// When live values last arrived from the panel; the widgets are updated from it.
    private(set) var lastRefresh: Date?
    /// Newest backup archive per server, loaded only while a backup widget is placed.
    private(set) var lastBackups: [String: WidgetSnapshot.Backup] = [:]
    /// The widget kinds the user has placed; replaced in tests.
    var installedWidgets: () async -> Set<String> = { await WidgetSync.installedKinds() }
    private(set) var busy: (serverID: String, action: ServerAction)?
    var selectedID: String?
    var actionError: Error?
    var eulaServer: Server?

    private var service: CraftyService?

    static let pollInterval: Duration = .seconds(5)
    static let historyWindow: TimeInterval = 3600
    /// The panel records stats every 30 s; denser live points would make the line jitter at its end.
    static let sampleSpacing: TimeInterval = 30

    // MARK: Derived

    var selected: Server? {
        guard let list = servers.value else { return nil }
        return list.first { $0.id == selectedID } ?? list.first
    }

    var crashed: [Server] { (servers.value ?? []).filter { stats[$0.id]?.crashed == true } }
    var onlineCount: Int { (servers.value ?? []).filter { stats[$0.id]?.running == true }.count }
    var playerCount: Int { stats.values.reduce(0) { $0 + $1.online } }

    // MARK: Loading

    /// Loads everything for `service` and keeps the values live until the task is cancelled
    /// (when the view disappears or the active panel changes).
    func run(with service: CraftyService) async {
        attach(service)
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Switching panels starts from scratch.
    func attach(_ service: CraftyService) {
        guard self.service !== service else { return }
        self.service = service
        servers = .idle; stats = [:]; history = [:]; consoleTail = [:]; liveProblem = nil; lastBackups = [:]
    }

    func load() async {
        guard let service else { return }
        if servers.value == nil { servers = .loading }
        do {
            let list = try await service.servers()
            servers = .loaded(list)
            await refresh()
            if selectedID == nil || !list.contains(where: { $0.id == selectedID }) { selectedID = busiest(list)?.id }
            await selectionChanged()
            await loadWidgetDetails(list)
        } catch {
            servers = .failed(error)
        }
    }

    /// Fetches the hour of history once per server; afterwards the poll appends live samples.
    func selectionChanged() async {
        guard let service, let server = selected else { return }
        if history[server.id] == nil, let samples = try? await service.statsHistory(serverID: server.id) {
            history[server.id] = samples
        }
        await refreshConsole(server)
    }

    private func refresh() async {
        guard let service, let list = servers.value, !list.isEmpty else { return }
        var problems: [PanelProblem] = []
        await withTaskGroup(of: (String, Result<ServerStats, Error>).self) { group in
            for server in list {
                group.addTask {
                    do { return (server.id, .success(try await service.stats(serverID: server.id))) }
                    catch { return (server.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let value):
                    stats[id] = value
                    appendSample(value, to: id)
                case .failure(let error):
                    problems.append(error.panelProblem)
                }
            }
        }
        // Only when nothing came back: a single failing server is shown by its own status.
        liveProblem = problems.count == list.count ? problems.first : nil
        if liveProblem == nil { lastRefresh = .now }
        if let server = selected { await refreshConsole(server) }
    }

    /// What only the widgets show: the last hour of every server and, for a backup widget, the newest archive.
    /// Loaded once per load rather than on every poll, and not at all without widgets.
    private func loadWidgetDetails(_ list: [Server]) async {
        guard let service else { return }
        let kinds = await installedWidgets()
        guard !kinds.isEmpty else { return }
        let wantsBackups = kinds.contains(WidgetKind.backup)
        await withTaskGroup(of: (String, [StatSample]?, WidgetSnapshot.Backup?).self) { group in
            for server in list {
                let needsHistory = history[server.id] == nil
                group.addTask {
                    let samples = needsHistory ? try? await service.statsHistory(serverID: server.id) : nil
                    let backup = wantsBackups ? await Self.newestBackup(serverID: server.id, service: service) : nil
                    return (server.id, samples, backup)
                }
            }
            for await (id, samples, backup) in group {
                if let samples { history[id] = samples }
                if let backup { lastBackups[id] = backup }
            }
        }
    }

    /// From the default backup configuration; nil where the panel cannot list archives (Crafty 4.7) or the user lacks the right.
    private nonisolated static func newestBackup(serverID: String, service: CraftyService) async -> WidgetSnapshot.Backup? {
        guard let config = try? await service.backupConfigs(serverID: serverID).first,
              let files = try? await service.backupFiles(serverID: serverID, config: config),
              let newest = files.max(by: { $0.created < $1.created }) else { return nil }
        return WidgetSnapshot.Backup(date: newest.created, configName: config.name)
    }

    private func appendSample(_ value: ServerStats, to id: String) {
        let now = Date.now
        guard var samples = history[id],
              samples.last.map({ now.timeIntervalSince($0.date) >= Self.sampleSpacing }) ?? true else { return }
        samples.append(StatSample(date: now, cpu: value.running ? value.cpu : 0,
                                  memBytes: value.running ? value.memBytes ?? 0 : 0))
        samples.removeAll { now.timeIntervalSince($0.date) > Self.historyWindow }
        history[id] = samples
    }

    private func refreshConsole(_ server: Server) async {
        guard let service, stats[server.id]?.running == true,
              let lines = try? await service.logs(serverID: server.id, fromFile: false) else { return }
        consoleTail[server.id] = Array(lines.suffix(3))
    }

    /// The running server with the most players; otherwise the first one.
    private func busiest(_ list: [Server]) -> Server? {
        list.filter { stats[$0.id]?.running == true }.max { (stats[$0.id]?.online ?? 0) < (stats[$1.id]?.online ?? 0) }
            ?? list.first
    }

    // MARK: Actions

    /// True when the panel accepted the action.
    @discardableResult
    func perform(_ action: ServerAction, on server: Server) async -> Bool {
        guard let service else { return false }
        busy = (server.id, action)
        defer { busy = nil }
        let accepted: Bool
        do {
            try await service.send(action, serverID: server.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            accepted = true
        } catch CraftyError.eulaRequired {
            eulaServer = server
            return false
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = error
            accepted = false
        }
        if let value = try? await service.stats(serverID: server.id) {
            stats[server.id] = value
            appendSample(value, to: server.id)
        }
        return accepted
    }

    func isBusy(_ server: Server) -> Bool { busy?.serverID == server.id }
}
