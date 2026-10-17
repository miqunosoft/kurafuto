import SwiftUI

/// App settings: switch panels, appearance, Face ID, sign out, legal.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage("pollSeconds") private var pollSeconds = 5.0
    @State private var confirmLogoutAll = false
    @State private var actionError: Error?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Panels") {
                        ForEach(app.instanceStore.instances) { inst in
                            Button { app.switchTo(inst) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(inst.name).foregroundStyle(.primary)
                                        Text(inst.baseURL.absoluteString).font(.mono(.caption)).foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    if inst.id == app.activeInstance?.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                        Button("Add Panel") { app.activeInstance = nil }
                    }

                    AppearanceSection()

                    Section {
                        Toggle("Lock with \(app.lock.kind.label)", isOn: Binding(
                            get: { app.lock.isEnabled },
                            set: { on in Task { await app.lock.setEnabled(on) } }))
                        .disabled(app.lock.kind == .unavailable)
                        Button("Sign Out All Sessions", role: .destructive) { confirmLogoutAll = true }
                        Button("Sign Out of This Panel", role: .destructive) { app.signOut() }
                    } header: {
                        Text("Security")
                    } footer: {
                        Text(app.lock.kind == .unavailable
                             ? "Set a device passcode to use the app lock."
                             : "Asks for \(app.lock.kind.label) when Kurafuto opens and before stopping, killing, deleting or restoring.")
                    }

                    Section("Refresh") {
                        Stepper("Live values every \(Int(pollSeconds)) s", value: $pollSeconds, in: 2...60)
                    }

                    Section("About") {
                        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                        Link("Website", destination: AppLinks.website)
                        Link("Source Code", destination: AppLinks.sourceCode)
                        Text("Unofficial app. Not affiliated with or endorsed by Arcadia Technology (Crafty Controller), Mojang or Microsoft.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle("Settings")
            .errorAlert($actionError)
            .confirmationDialog("End all sessions for this user?", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    // Signing out locally after a failed invalidation would leave the other sessions valid unnoticed.
                    Task { if await $actionError.capture({ try await app.service.invalidateAllSessions() }) { app.signOut() } }
                }
            }
        }
    }
}

/// Theme mode and the per-metric accent colors.
struct AppearanceSection: View {
    private let appearance = Appearance.shared

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases) { mode in
                    ThemeModeTile(mode: mode, selected: appearance.mode == mode) {
                        withAnimation(.snappy) { appearance.mode = mode }
                    }
                }
            }
            .padding(.vertical, 6)

            ForEach(AccentRole.allCases) { role in
                AccentPicker(role: role, appearance: appearance)
            }

            Button("Reset Colors") { withAnimation(.snappy) { appearance.resetAccents() } }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Each metric keeps its color on the dashboard, gauges and charts.")
        }
    }
}

/// A miniature of the dashboard in one theme mode.
private struct ThemeModeTile: View {
    let mode: ThemeMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(text.opacity(0.85)).frame(width: 30, height: 5)
                    HStack(spacing: 4) {
                        Circle().stroke(AccentRole.cpu.defaultPreset.color(for: mode), lineWidth: 3).frame(width: 16, height: 16)
                        Circle().stroke(AccentRole.ram.defaultPreset.color(for: mode), lineWidth: 3).frame(width: 16, height: 16)
                    }
                    RoundedRectangle(cornerRadius: 3).fill(text.opacity(0.35)).frame(height: 5)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface(for: mode), in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
                .background(Theme.background(for: mode), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1)
                )
                Text(mode.label).font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // The tile previews its own mode, not the current theme.
    private var text: Color { Theme.primaryText(for: mode) }
}

private struct AccentPicker: View {
    let role: AccentRole
    let appearance: Appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                IconTile(symbol: role.symbol, color: appearance.color(for: role), size: 28)
                Text(role.label)
                Spacer()
                Text(appearance.preset(for: role).label)
                    .font(.mono(.caption)).foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 0) {
                ForEach(AccentPreset.allCases) { preset in
                    let selected = appearance.preset(for: role) == preset
                    Button {
                        withAnimation(.snappy) { appearance.setPreset(preset, for: role) }
                    } label: {
                        Circle()
                            .fill(preset.color(for: appearance.mode))
                            .frame(width: 26, height: 26)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(Theme.onAccent)
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? preset.color(for: appearance.mode) : .clear, lineWidth: 2))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(role.label) color \(preset.label)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum AppLinks {
    static let sourceCode = URL(string: "https://github.com/miquno/kurafuto") ?? URL(filePath: "/")
    static let privacyPolicy = URL(string: "https://getkurafuto.app/privacy/") ?? URL(filePath: "/")
    static let website = URL(string: "https://getkurafuto.app") ?? URL(filePath: "/")
}

#Preview { SettingsView().environment(AppState.preview) }
