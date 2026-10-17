import AppIntents
import SwiftUI
import WidgetKit

@main
struct KurafutoWidgets: WidgetBundle {
    var body: some Widget {
        ServerWidget()
        LoadWidget()
        PlayersWidget()
        BackupWidget()
        PanelWidget()
        ServerActivityWidget()
    }
}

/// One server: players ring (small), CPU and RAM (medium), everything with shortcuts (large), and on the Lock Screen.
struct ServerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.server, intent: SelectServerIntent.self, provider: SnapshotProvider()) { entry in
            ServerWidgetView(entry: entry)
        }
        .configurationDisplayName("Server")
        .description("Status and players of one server.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct LoadWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.load, intent: SelectServerIntent.self, provider: SnapshotProvider()) { entry in
            LoadWidgetView(entry: entry)
        }
        .configurationDisplayName("Server Load")
        .description("CPU and RAM of one server over the last hour.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct PlayersWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.players, intent: SelectServerIntent.self, provider: SnapshotProvider()) { entry in
            PlayersWidgetView(entry: entry)
        }
        .configurationDisplayName("Players")
        .description("Who is online on one server.")
        .supportedFamilies([.systemMedium])
    }
}

struct BackupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.backup, intent: SelectServerIntent.self, provider: SnapshotProvider()) { entry in
            BackupWidgetView(entry: entry)
        }
        .configurationDisplayName("Backup")
        .description("The latest backup of one server.")
        .supportedFamilies([.systemSmall])
    }
}

/// Every server of the panel, crashed ones first.
struct PanelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.panel, provider: SnapshotProvider()) { entry in
            PanelWidgetView(entry: entry)
        }
        .configurationDisplayName("Panel")
        .description("Status and players of every server on your panel.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var serverID: String?

    var server: WidgetSnapshot.Server? { snapshot?.server(id: serverID) }
}

/// Reads the snapshot the app wrote. The app reloads the widgets when it changes, so there is one entry and no schedule.
struct SnapshotProvider: AppIntentTimelineProvider, TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    // AppIntentTimelineProvider (widgets that show one server)
    func snapshot(for configuration: SelectServerIntent, in context: Context) async -> SnapshotEntry {
        entry(serverID: configuration.server?.id, preview: context.isPreview)
    }

    func timeline(for configuration: SelectServerIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [entry(serverID: configuration.server?.id, preview: false)], policy: .never)
    }

    // TimelineProvider (PanelWidget)
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(serverID: nil, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [entry(serverID: nil, preview: false)], policy: .never))
    }

    /// The gallery shows sample servers until the app has written a snapshot.
    private func entry(serverID: String?, preview: Bool) -> SnapshotEntry {
        let stored = WidgetSnapshotStore.shared.load()
        return SnapshotEntry(date: .now, snapshot: stored ?? (preview ? .sample : nil), serverID: serverID)
    }
}

struct SelectServerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Server"
    static let description = IntentDescription("Choose the server this widget shows.")

    @Parameter(title: "Server")
    var server: ServerEntity?
}

/// A server from the snapshot; the widget's configuration lists the servers the app last saw.
struct ServerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static let defaultQuery = ServerQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerEntity] { all() }

    private func all() -> [ServerEntity] {
        (WidgetSnapshotStore.shared.load()?.servers ?? []).map { ServerEntity(id: $0.id, name: $0.name) }
    }
}
