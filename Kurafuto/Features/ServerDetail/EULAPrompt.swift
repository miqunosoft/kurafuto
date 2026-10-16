import SwiftUI

extension View {
    /// Asks to accept the Minecraft EULA after the panel refused to start `server` without it.
    /// Accepting also starts the server (the panel does both in one step).
    func eulaPrompt(for server: Binding<Server?>, onAccepted: @escaping () async -> Void) -> some View {
        modifier(EULAPrompt(server: server, onAccepted: onAccepted))
    }
}

private struct EULAPrompt: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Binding var server: Server?
    let onAccepted: () async -> Void
    @State private var error: Error?

    // The same page the Crafty web panel links to.
    private static let eula = URL(string: "https://www.minecraft.net/en-us/eula") ?? URL(filePath: "/")

    func body(content: Content) -> some View {
        content.alert("Accept the Minecraft EULA?",
                      isPresented: Binding(get: { server != nil }, set: { if !$0 { server = nil } }),
                      presenting: server) { s in
            Button("Accept and Start") {
                Task {
                    if await $error.capture({ try await app.service.acceptEULA(serverID: s.id) }) {
                        app.followInLiveActivity(.start, on: s)
                    }
                    await onAccepted()
                }
            }
            Button("Read the EULA") { openURL(Self.eula) }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            Text("\(s.serverName) can only start after you accept the Minecraft End User License Agreement.")
        }
        .errorAlert($error)
    }
}

#Preview {
    Text("Server").eulaPrompt(for: .constant(MockData.servers[0])) {}.environment(AppState.preview)
}
