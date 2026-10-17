import SwiftUI

/// Webhooks (Discord, Mattermost, Slack, Teams) with triggers. The panel sends them; the app only edits the entries.
struct WebhooksView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[Webhook]> = .idle
    @State private var editing: Webhook?
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?
    @State private var testSent: String?

    var body: some View {
        LoadableView(state: state, retry: load) { hooks in
            List {
                Group {
                    ForEach(hooks) { h in
                        Button { editing = h } label: { row(h) }
                            .swipeActions(edge: .leading) {
                                Button { Task { await test(h) } } label: { Label("Send Test", systemImage: "paperplane") }
                                    .tint(Theme.accent)
                            }
                            .contextMenu {
                                Button { Task { await test(h) } } label: { Label("Send Test", systemImage: "paperplane") }
                            }
                    }
                    .onDelete { idx in
                        let doomed = idx.map { hooks[$0] }
                        confirm = ConfirmAction(title: String(localized: "Delete \(doomed.count) webhooks?"),
                                                message: doomed.map(\.name).joined(separator: ", "),
                                                buttonLabel: String(localized: "Delete")) {
                            await $actionError.capture {
                                for h in doomed { try await app.service.deleteWebhook(id: h.id, serverID: server.id) }
                            }
                            await load()
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .entrance()
            .refreshable { await load() }
            .overlay { if hooks.isEmpty { ContentUnavailableView("No Webhooks", systemImage: "bell.slash") } }
        }
        .navigationTitle("Webhooks")
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .alert("Test Sent", isPresented: Binding(get: { testSent != nil }, set: { if !$0 { testSent = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The panel sent a test message to “\(testSent ?? "")”.")
        }
        .toolbar {
            Button { editing = .new() } label: { Image(systemName: "plus") }
                .accessibilityLabel("New webhook")
        }
        .sheet(item: $editing) { h in
            WebhookEditor(webhook: h) { saved in
                Task {
                    await $actionError.capture { try await app.service.saveWebhook(saved, serverID: server.id) }
                    await load()
                }
            }
        }
        .task { await load() }
    }

    private func row(_ h: Webhook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack {
                Text(h.name).font(.headline).foregroundStyle(.primary)
                Spacer()
                Text(h.type).font(.mono(.caption2, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.sunken, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                    .foregroundStyle(Theme.secondaryText)
            }
            // Only the host: the rest of a webhook address is usually its secret.
            if let host = URLComponents(string: h.url)?.host {
                Text(host).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
            }
            Text(h.triggers.isEmpty ? String(localized: "No triggers") : h.triggers.map(WebhookTrigger.label(for:)).joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.secondaryText)
            if !h.enabled { Text("DISABLED").font(.mono(.caption2, weight: .semibold)).foregroundStyle(Theme.warning) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the webhook. Swipe right to send a test message.")
    }

    private func test(_ h: Webhook) async {
        if await $actionError.capture({ try await app.service.testWebhook(id: h.id, serverID: server.id) }) {
            testSent = h.name
        }
    }

    private func load() async {
        do { state = .loaded(try await app.service.webhooks(serverID: server.id)) } catch { state = .failed(error) }
    }
}

struct WebhookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var webhook: Webhook
    let onSave: (Webhook) -> Void

    /// Known triggers first, then any the panel stored that this version does not know.
    private var triggerNames: [String] {
        WebhookTrigger.allCases.map(\.rawValue) + webhook.triggers.filter { WebhookTrigger(rawValue: $0) == nil }
    }

    private var variables: [String] {
        let extra = webhook.triggers.compactMap(WebhookTrigger.init(rawValue:)).flatMap(\.extraVariables)
        return WebhookTrigger.commonVariables + extra.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("Name", text: $webhook.name)
                        Picker("Service", selection: $webhook.type) {
                            ForEach(Webhook.providers + (Webhook.providers.contains(webhook.type) ? [] : [webhook.type]), id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        TextField("Webhook URL", text: $webhook.url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.mono(.footnote))
                        TextField("Bot name", text: $webhook.botName)
                    } footer: {
                        Text("http:// and https:// addresses work. The panel sends the messages, not this iPhone.")
                    }
                    Section("Triggers") {
                        ForEach(triggerNames, id: \.self) { name in
                            Toggle(WebhookTrigger.label(for: name), isOn: Binding(get: { webhook.triggers.contains(name) }, set: { on in
                                if on { webhook.triggers.append(name) } else { webhook.triggers.removeAll { $0 == name } }
                            }))
                        }
                    }
                    Section {
                        TextEditor(text: $webhook.body)
                            .font(.mono(.footnote)).frame(minHeight: 90)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Message")
                    } header: {
                        Text("Message")
                    } footer: {
                        Text("Jinja2 template, e.g. {{ server_name }}. Available: \(variables.joined(separator: ", ")).")
                            .font(.mono(.caption2))
                    }
                    Section {
                        if webhook.type == "Discord" {
                            ColorPicker("Embed color", selection: Binding(get: { Color(hex: webhook.color) ?? Theme.accent },
                                                                          set: { webhook.color = $0.hex ?? Webhook.defaultColor }),
                                        supportsOpacity: false)
                        }
                        Toggle("Enabled", isOn: $webhook.enabled)
                    } footer: {
                        if let problem = webhook.problem, !webhook.url.isEmpty || !webhook.name.isEmpty {
                            Text(problem).foregroundStyle(Theme.warning)
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(webhook.id == 0 ? String(localized: "New Webhook") : webhook.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(webhook); dismiss() }.disabled(webhook.problem != nil)
                }
            }
        }
    }
}

/// `#rrggbb`, the format the panel stores webhook colors in.
private extension Color {
    init?(hex: String) {
        guard Webhook.isValidColor(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hex: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}

#Preview("Webhooks") {
    NavigationStack { WebhooksView(server: MockData.servers[0]) }.environment(AppState.preview)
}

#Preview("Webhook editor") {
    WebhookEditor(webhook: MockData.webhooks[0]) { _ in }
}
