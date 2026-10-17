import SwiftUI

/// Player management. Crafty has no dedicated API endpoints for this –
/// everything goes through console commands (stdin) plus reading ops.json / whitelist.json / banned-players.json.
struct PlayersView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let server: Server
    @State private var online: [String] = []
    @State private var newName = ""
    @State private var toast: String?
    @State private var actionError: Error?
    @State private var liveProblem: PanelProblem?

    var body: some View {
        List {
            Group {
                if let liveProblem {
                    StaleValuesBanner(problem: liveProblem).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section("Online (\(online.count))") {
                    if online.isEmpty {
                        Text("Nobody online").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(online, id: \.self) { name in
                        HStack {
                            // Decorative; at accessibility sizes the name needs the width.
                            if !typeSize.isAccessibilitySize { PlayerInitialsAvatar(name: name) }
                            Text(name).font(.mono(.body))
                            Spacer()
                            Menu {
                                Button("Make Operator") { cmd("op \(name)") }
                                Button("Remove Operator") { cmd("deop \(name)") }
                                Button("Creative Mode") { cmd("gamemode creative \(name)") }
                                Button("Survival Mode") { cmd("gamemode survival \(name)") }
                                Button("Teleport to Me") { cmd("tp \(name) \(app.activeInstance?.username ?? "")") }
                                Divider()
                                Button("Kick", role: .destructive) { cmd("kick \(name)") }
                                Button("Ban", role: .destructive) { cmd("ban \(name)") }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Actions for \(name)")
                        }
                    }
                }

                Section {
                    TextField("Player name", text: $newName).textInputAutocapitalization(.never)
                    HStack {
                        Button("Whitelist +") { cmd("whitelist add \(newName)") }
                        Button("Whitelist −") { cmd("whitelist remove \(newName)") }
                        Button("Unban") { cmd("pardon \(newName)") }
                    }
                    .buttonStyle(InstrumentButtonStyle(kind: .tinted, color: Theme.players))
                    .disabled(newName.isEmpty)
                } header: { Text("Whitelist & Bans") } footer: {
                    Text("Sent to your server as a console command.")
                }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
        .navigationTitle("Players")
        .errorAlert($actionError)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.mono(.footnote)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                    .padding()
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            while !Task.isCancelled {
                do {
                    online = try await app.service.stats(serverID: server.id).players
                    liveProblem = nil
                } catch { liveProblem = error.panelProblem }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func cmd(_ c: String) {
        Task {
            guard await $actionError.capture({ try await app.service.sendCommand(c, serverID: server.id) }) else { return }
            let sent = String(localized: "Sent: \(c)")
            withAnimation { toast = sent }
            AccessibilityNotification.Announcement(sent).post()
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toast = nil }
        }
    }
}

/// Local placeholder avatar. Skin services are deliberately not used: they would send player names
/// and the user's IP address to a third party (see docs/decisions/0002-no-data-collection.md).
struct PlayerInitialsAvatar: View {
    let name: String
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 32
    var body: some View {
        Text(name.prefix(2).uppercased())
            .font(.caption.weight(.bold).monospaced())
            .foregroundStyle(Theme.players)
            .frame(width: size, height: size)
            .background(Theme.players.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}
