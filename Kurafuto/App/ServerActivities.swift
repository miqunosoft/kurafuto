// Activity is not Sendable yet; it is only touched on the main actor here.
@preconcurrency import ActivityKit
import UIKit

/// Live Activities for a server's start-up and backups the user started in the app (ADR 0011). Without a push relay
/// only the app can update them: it does so from the panel while it runs, for about half a minute in the background,
/// and again when it is opened. In between they turn stale, which their view says.
@MainActor
final class ServerActivities {
    typealias Attributes = ServerActivityAttributes

    /// Ended activities stay on the Lock Screen this long.
    static let keepEnded: TimeInterval = 15 * 60
    /// iOS shows an activity as stale after this long without an update; a running app refreshes it more often.
    static let staleAfter: TimeInterval = 60
    static let heartbeat: Duration = .seconds(20)
    /// Reconnects after the panel socket dropped (usually because iOS suspended the app).
    static let backupReconnects = 2

    private var watchers: [String: Task<Void, Never>] = [:]

    nonisolated init() {}

    /// Follows a start or backup the panel accepted; other actions are ignored. `name` is nil while the app lock is on.
    func follow(_ action: ServerAction, serverID: String, name: String?, service: CraftyService) {
        let kind: Attributes.Kind
        switch action {
        case .start: kind = .startUp
        case .backup: kind = .backup
        default: return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = Attributes(kind: kind, serverID: serverID, serverName: name, started: .now,
                                    mode: Appearance.shared.mode, accent: Appearance.shared.preset(for: .accent))
        let key = "\(kind.rawValue)/\(serverID)"
        watchers[key]?.cancel()
        watchers[key] = Task {
            let background = BackgroundTime()
            defer { background.end() }
            switch kind {
            case .startUp: await Self.followStartUp(attributes, service: service)
            case .backup: await Self.followBackup(attributes, service: service)
            }
        }
    }

    /// When the user signs out or switches panels; at launch also the ones a previous run could not finish.
    func endAll() async {
        watchers.values.forEach { $0.cancel() }
        watchers = [:]
        for activity in Activity<Attributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: Following

    private static func followStartUp(_ attributes: Attributes, service: CraftyService) async {
        guard let shown = ShownActivity(attributes, state: .init(phase: .running)) else { return }
        var watch = StartUpWatch(started: attributes.started)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { break }
            let phase = watch.phase(after: try? await service.stats(serverID: attributes.serverID), at: .now)
            if phase == .running { continue }
            return await shown.end(phase.map { .init(phase: $0) })
        }
        await shown.end(nil)
    }

    /// The activity appears with the panel's first progress event, so a panel whose socket is unreachable shows none.
    private static func followBackup(_ attributes: Attributes, service: CraftyService) async {
        var shown: ShownActivity?
        for attempt in 0...backupReconnects {
            if attempt > 0 {
                guard shown != nil, await untilActive() else { break }
            }
            // After a reconnect a backup that ended meanwhile stays silent; snapshot backups are silent until they end.
            for await progress in service.backupProgress(serverID: attributes.serverID,
                                                         idleTimeout: attempt == 0 ? nil : .seconds(30)) {
                switch progress {
                case .running(let done):
                    let state = Attributes.ContentState(phase: .running, progress: done)
                    if let shown { await shown.show(state) } else {
                        shown = ShownActivity(attributes, state: state)
                        if shown == nil { return }
                    }
                case .finished(let failed):
                    if let failed {
                        let state = Attributes.ContentState(phase: failed ? .failed : .succeeded, progress: failed ? nil : 1)
                        await (shown ?? ShownActivity(attributes, state: state))?.end(state)
                    } else {
                        await shown?.end(nil)
                    }
                    return
                }
            }
            if Task.isCancelled { break }
        }
        await shown?.end(nil)
    }

    /// Waits until the user is back in the app; false when cancelled.
    private static func untilActive() async -> Bool {
        while UIApplication.shared.applicationState != .active {
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return false }
        }
        return !Task.isCancelled
    }
}

/// Reads a start-up from the panel's stats. The process runs within seconds of the start, but players can only join
/// once the server answers the panel's ping.
struct StartUpWatch {
    /// A server that is neither running nor waiting to start by then did not start.
    static let launchLimit: TimeInterval = 90
    /// A server that runs but never answers (some server types cannot be pinged) is no longer followed after this.
    static let readyLimit: TimeInterval = 10 * 60

    let started: Date
    private(set) var launched = false

    init(started: Date) { self.started = started }

    /// `.running` while starting, nil when it is no longer worth following. Stats that failed to load count as no news.
    mutating func phase(after stats: ServerStats?, at now: Date) -> ServerActivityAttributes.Phase? {
        if let stats {
            if stats.running && stats.answersPing { return .succeeded }
            if stats.running || stats.waitingStart {
                launched = true
            } else if launched {
                return .failed
            }
        }
        let elapsed = now.timeIntervalSince(started)
        if !launched && elapsed > Self.launchLimit { return .failed }
        return elapsed > Self.readyLimit ? nil : .running
    }
}

/// One requested Live Activity. While it runs, a heartbeat moves its stale date forward; once iOS suspends the app,
/// the heartbeat stops and the activity turns stale.
@MainActor
private final class ShownActivity {
    typealias Attributes = ServerActivityAttributes

    private let activity: Activity<Attributes>
    private var state: Attributes.ContentState
    private var heartbeat: Task<Void, Never>?

    /// Nil when iOS refuses, for example because the app is no longer in the foreground.
    init?(_ attributes: Attributes, state: Attributes.ContentState) {
        guard let activity = try? Activity.request(attributes: attributes, content: Self.content(state), pushType: nil) else {
            return nil
        }
        self.activity = activity
        self.state = state
        heartbeat = Task { [weak self] in
            while (try? await Task.sleep(for: ServerActivities.heartbeat)) != nil {
                await self?.refresh()
            }
        }
    }

    /// Updates only for a visible change: a new phase or at least one more percent.
    func show(_ new: Attributes.ContentState) async {
        let step = abs((new.progress ?? 0) - (state.progress ?? 0))
        guard new.phase != state.phase || step >= 0.01 else { return }
        state = new
        await refresh()
    }

    /// With a final state the activity stays a while; without one (no result, given up, cancelled) it disappears.
    func end(_ final: Attributes.ContentState?) async {
        heartbeat?.cancel()
        let policy: ActivityUIDismissalPolicy = final == nil ? .immediate : .after(.now + ServerActivities.keepEnded)
        await activity.end(final.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    }

    private func refresh() async {
        await activity.update(Self.content(state))
    }

    private static func content(_ state: Attributes.ContentState) -> ActivityContent<Attributes.ContentState> {
        ActivityContent(state: state, staleDate: .now + ServerActivities.staleAfter)
    }
}

/// The half minute iOS grants after the user leaves the app, so an activity keeps updating briefly.
@MainActor
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Live Activity") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
