import ActivityKit
import Foundation

/// A Live Activity for a server's start-up or backup (ADR 0011). The app starts, updates and ends it on the device;
/// the widget extension only draws it. No push token is requested, so nothing goes through Apple's push service.
struct ServerActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable { case startUp, backup }

    enum Phase: String, Codable, Hashable { case running, succeeded, failed }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// Share of the backup that is done, 0...1; nil for start-ups.
        var progress: Double?
    }

    let kind: Kind
    let serverID: String
    /// Nil while the app lock is on, so the Lock Screen does not name the user's servers.
    let serverName: String?
    let started: Date
    let mode: ThemeMode
    let accent: AccentPreset
}

extension ServerActivityAttributes {
    var displayName: String { serverName ?? String(localized: "Server") }

    var symbol: String { kind == .startUp ? "play.fill" : "externaldrive.fill" }

    /// Start-ups open the console, backups the server's details.
    var link: URL? { ServerLink.url(serverID: serverID, screen: kind == .startUp ? .console : .details) }

    func status(_ state: ContentState) -> String {
        switch (kind, state.phase) {
        case (.startUp, .running): String(localized: "Starting…")
        case (.startUp, .succeeded): String(localized: "Ready for players")
        case (.startUp, .failed): String(localized: "Did not start")
        case (.backup, .running): String(localized: "Backing up…")
        case (.backup, .succeeded): String(localized: "Backup finished")
        case (.backup, .failed): String(localized: "Backup failed")
        }
    }
}
