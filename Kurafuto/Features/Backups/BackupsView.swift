import SwiftUI

/// Backup manager: backup configurations, their archives, restore/delete, back up now.
/// Crafty 4.7 cannot list archives over the API; the screen then links to the web panel for them.
struct BackupsView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var configs: Loadable<[BackupConfig]> = .idle
    @State private var selectedID: String?
    @State private var files: Loadable<[BackupFile]?> = .idle
    @State private var editing: BackupConfig?
    @State private var confirm: ConfirmAction?
    @State private var running = false
    @State private var actionError: Error?
    @State private var notice: Notice?

    struct Notice { let title: String; let message: String }

    var body: some View {
        LoadableView(state: configs, retry: loadConfigs) { list in content(list) }
            .navigationTitle("Backups")
            .toolbar {
                Button { editing = BackupConfig(id: "", name: "", location: configs.value?.first?.location ?? "") } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New backup configuration")
            }
            .sheet(item: $editing) { c in
                BackupConfigEditor(config: c, canChooseLocation: app.access?.isSuperuser == true) { saved in
                    Task {
                        await $actionError.capture {
                            try await app.service.saveBackupConfig(saved, includeLocation: app.access?.isSuperuser == true,
                                                                   serverID: server.id)
                        }
                        await loadConfigs()
                    }
                }
            }
            .destructiveConfirmation($confirm)
            .errorAlert($actionError)
            .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
                   presenting: notice) { _ in
                Button("OK") {}
            } message: { Text($0.message) }
            .task { await loadConfigs() }
    }

    private func content(_ list: [BackupConfig]) -> some View {
        List {
            Group {
                if list.count > 1 {
                    Picker("Configuration", selection: $selectedID) {
                        ForEach(list) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if let c = list.first(where: { $0.id == selectedID }) {
                    settings(c)
                    Section {
                        Button { Task { await backUp(c) } } label: {
                            HStack {
                                Label("Back Up Now", systemImage: "externaldrive.badge.plus").foregroundStyle(Theme.storage)
                                Spacer()
                                if running { ProgressView() }
                            }
                        }
                        .disabled(running)
                    }
                    Section("Archives") { archives(c) }
                    if !c.isDefault {
                        Section {
                            Button("Delete Configuration", role: .destructive) {
                                confirm = ConfirmAction(title: String(localized: "Delete configuration?"),
                                                        message: String(localized: "\(c.name): backup schedules that use it stop running. Archives stay on the panel."),
                                                        buttonLabel: String(localized: "Delete")) {
                                    await $actionError.capture { try await app.service.deleteBackupConfig(id: c.id, serverID: server.id) }
                                    await loadConfigs()
                                }
                            }
                        }
                    }
                } else {
                    Text("No backup configuration yet.").foregroundStyle(Theme.secondaryText)
                }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
        .refreshable { await loadFiles() }
        .onChange(of: selectedID) { Task { await loadFiles() } }
    }

    private func settings(_ c: BackupConfig) -> some View {
        Section("Settings") {
            LabeledContent("Destination") { Text(c.location).font(.mono(.caption)) }
            LabeledContent("Keep") { Text(c.maxBackups == 0 ? "All archives" : "\(c.maxBackups) archives") }
            LabeledContent("Compressed") { Text(c.compress ? "Yes" : "No") }
            LabeledContent("Stop server") { Text(c.shutdown ? "Yes" : "No") }
            if c.kind == .snapshot { LabeledContent("Type") { Text("Snapshot") } }
            if !c.beforeCommand.isEmpty { LabeledContent("Before") { Text(c.beforeCommand).font(.mono(.caption)) } }
            if !c.afterCommand.isEmpty { LabeledContent("After") { Text(c.afterCommand).font(.mono(.caption)) } }
            if !c.excludedPaths.isEmpty {
                LabeledContent("Excluded") { Text(c.excludedPaths.joined(separator: ", ")).font(.mono(.caption)) }
            }
            Button("Edit Configuration") { editing = c }.tint(Theme.accent)
        }
    }

    @ViewBuilder
    private func archives(_ c: BackupConfig) -> some View {
        switch files {
        case .loaded(.some(let list)) where list.isEmpty:
            Text("No archives yet.").foregroundStyle(Theme.secondaryText)
        case .loaded(.some(let list)):
            ForEach(list) { f in
                Menu {
                    Button { confirmRestore(f, c, inPlace: true) } label: {
                        Label("Restore Over Current Files", systemImage: "clock.arrow.circlepath")
                    }
                    Button { confirmRestore(f, c, inPlace: false) } label: {
                        Label("Replace All Server Files", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) { confirmDelete(f, c) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "archivebox.fill", color: Theme.storage, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            // Text(_:format:) would apply the device's time zone from the environment.
                            Text(f.created.formatted(Self.panelTime)).font(.headline).foregroundStyle(.primary)
                            Text(f.name).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .tint(.primary)
                .accessibilityHint("Restore or delete this archive")
                .swipeActions {
                    Button(role: .destructive) { confirmDelete(f, c) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        case .loaded(.none):
            VStack(alignment: .leading, spacing: 8) {
                Text(c.kind == .snapshot
                     ? "Snapshot archives are not listed over the API. Restore them in the web panel."
                     : "This panel version cannot list archives over the API (Crafty 4.11 or later can). Restore and delete them in the web panel.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if let url = app.webPanelURL(serverID: server.id, subpage: "backup") {
                    Link("Open Web Panel", destination: url).font(.subheadline).tint(Theme.accent)
                }
            }
        case .failed(let e):
            Text(e.panelProblem.message(for: e)).foregroundStyle(Theme.danger)
        case .idle, .loading:
            ProgressView()
        }
    }

    /// Archive names carry the panel host's wall-clock time; `BackupFile` keeps it in UTC so it shows unchanged.
    private static let panelTime = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: .gmt)

    private func confirmRestore(_ f: BackupFile, _ c: BackupConfig, inPlace: Bool) {
        confirm = ConfirmAction(
            title: inPlace ? String(localized: "Restore backup?") : String(localized: "Replace server files?"),
            message: inPlace
                ? String(localized: "\(f.name): the server stops and the archive is unpacked over its current files. Files that are not in the archive stay.")
                : String(localized: "\(f.name): the server stops, its folder is emptied and the archive is unpacked. Everything that is not in the archive is lost."),
            buttonLabel: inPlace ? String(localized: "Restore") : String(localized: "Replace")
        ) {
            let ok = await $actionError.capture {
                try await app.service.restoreBackup(f, configID: c.id, inPlace: inPlace, serverID: server.id)
            }
            if ok {
                notice = Notice(title: String(localized: "Restore Started"),
                                message: String(localized: "The panel restores \(f.name) in the background. Start the server again when it is done."))
            }
        }
    }

    private func confirmDelete(_ f: BackupFile, _ c: BackupConfig) {
        confirm = ConfirmAction(title: String(localized: "Delete backup?"), message: f.name, buttonLabel: String(localized: "Delete")) {
            await $actionError.capture { try await app.service.deleteBackup(f, configID: c.id, serverID: server.id) }
            await loadFiles()
        }
    }

    private func backUp(_ c: BackupConfig) async {
        running = true
        let ok = await $actionError.capture { try await app.service.startBackup(serverID: server.id, configID: c.id) }
        running = false
        if ok {
            app.followInLiveActivity(.backup, on: server)
            notice = Notice(title: String(localized: "Backup Started"),
                            message: String(localized: "The panel creates the archive in the background. Pull down to refresh the list."))
        }
        await loadFiles()
    }

    private func loadConfigs() async {
        do {
            let list = try await app.service.backupConfigs(serverID: server.id)
            configs = .loaded(list)
            if !list.contains(where: { $0.id == selectedID }) { selectedID = list.first?.id }
            await loadFiles()
        } catch { configs = .failed(error) }
    }

    private func loadFiles() async {
        guard let c = configs.value?.first(where: { $0.id == selectedID }) else { files = .loaded([]); return }
        do { files = .loaded(try await app.service.backupFiles(serverID: server.id, config: c)) }
        catch { files = .failed(error) }
    }
}

struct BackupConfigEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var config: BackupConfig
    /// Only superusers may set the destination; the panel picks it for everyone else.
    let canChooseLocation: Bool
    let onSave: (BackupConfig) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Name", text: $config.name)
                    if canChooseLocation {
                        Section {
                            TextField("/crafty/backups/…", text: $config.location)
                                .monospaced().textInputAutocapitalization(.never).autocorrectionDisabled()
                        } header: { Text("Destination on the panel host") }
                    }
                    Section("Archives") {
                        Stepper(config.maxBackups == 0 ? "Keep all" : "Keep \(config.maxBackups)",
                                value: $config.maxBackups, in: 0...999)
                        Toggle("Compress", isOn: $config.compress)
                        Toggle("Stop server during backup", isOn: $config.shutdown)
                    }
                    Section {
                        command("Before", "save-off", $config.beforeCommand)
                        command("After", "save-on", $config.afterCommand)
                    } header: { Text("Console commands") }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(config.id.isEmpty ? "New Configuration" : "Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(prepared); dismiss() }.disabled(!isComplete)
                }
            }
        }
    }

    private func command(_ label: LocalizedStringKey, _ example: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(example))
                .monospaced().multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    /// The panel requires names of at least three characters.
    private var isComplete: Bool {
        prepared.name.count >= 3 && (!canChooseLocation || !prepared.location.isEmpty)
    }

    private var prepared: BackupConfig {
        var c = config
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        c.location = c.location.trimmingCharacters(in: .whitespaces)
        c.beforeCommand = c.beforeCommand.trimmingCharacters(in: .whitespaces)
        c.afterCommand = c.afterCommand.trimmingCharacters(in: .whitespaces)
        return c
    }
}

#Preview {
    NavigationStack { BackupsView(server: MockData.servers[0]) }.environment(AppState.preview)
}
