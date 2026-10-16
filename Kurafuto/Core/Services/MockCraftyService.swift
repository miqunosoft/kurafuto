import Foundation

/// Complete in-memory implementation of `CraftyService`.
/// - Simulates network latency, status transitions (start takes a few seconds) and a live console.
/// - `failureRate` > 0 produces random errors to exercise the error UI.
final class MockCraftyService: CraftyService, @unchecked Sendable {
    private let lock = NSLock()
    private var servers = MockData.servers
    private var stats = MockData.stats
    private var schedules: [String: [Schedule]] = [:]
    private var backupConfigs: [String: [BackupConfig]] = [:]
    /// Keyed by "serverID/configID".
    private var backups: [String: [BackupFile]] = [:]
    private var webhooks: [String: [Webhook]] = [:]
    private var files: [String: PanelFile] = ["server.properties": PanelFile(content: MockData.serverProperties, modifiedEpoch: 1)]
    private var createdFolders: Set<String> = []
    private var deletedPaths: Set<String> = []
    /// Uploaded files by path, with the panel-style size text.
    private var uploadedFiles: [String: String] = [:]
    private var users = MockData.users
    private var roles = MockData.roles
    private var announcementList = MockData.announcements
    private var console: [String: [String]] = [:]
    /// Java servers created in the demo start only after their EULA is accepted, like on a real panel.
    private var needsEULA: Set<String> = []

    var latency: Duration
    var failureRate: Double
    /// What `panelAccess()` reports; the demo signs in as a superuser.
    var grantedAccess: PanelAccess

    init(latency: Duration = .milliseconds(350), failureRate: Double = 0,
         access: PanelAccess = PanelAccess(isSuperuser: true, permissions: CraftyPermissions(mask: "000"), userID: 1)) {
        self.latency = latency
        self.failureRate = failureRate
        self.grantedAccess = access
    }

    private func simulate() async throws {
        try await Task.sleep(for: latency)
        if Double.random(in: 0..<1) < failureRate {
            throw CraftyError.transport(URLError(.timedOut))
        }
    }

    private func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    // MARK: Auth
    func login(username: String, password: String, totp: String?) async throws -> String {
        try await simulate()
        guard !password.isEmpty else { throw CraftyError.unauthorized }
        return "mock-token-\(username)"
    }
    func invalidateAllSessions() async throws { try await simulate() }
    func healthCheck() async throws -> Bool { try await simulate(); return true }

    // MARK: Servers
    func servers() async throws -> [Server] { try await simulate(); return sync { servers } }

    func server(id: String) async throws -> Server {
        try await simulate()
        guard let s = sync({ servers.first { $0.id == id } }) else { throw CraftyError.server(code: "NOT_FOUND", detail: nil) }
        return s
    }

    func stats(serverID: String) async throws -> ServerStats {
        try await simulate()
        return sync {
            var s = stats[serverID] ?? ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20, players: [])
            if s.running { // add some movement to the values
                s.cpu = max(1, min(95, s.cpu + Double.random(in: -6...6)))
                s.memPercent = max(5, min(90, s.memPercent + Double.random(in: -2...2)))
                s.memBytes = s.memBytes.map { max(0, $0 * (1 + Double.random(in: -0.02...0.02))) }
                stats[serverID] = s
            }
            return s
        }
    }

    func send(_ action: ServerAction, serverID: String) async throws {
        try await simulate()
        if action == .start, sync({ needsEULA.contains(serverID) }) { throw CraftyError.eulaRequired }
        switch action {
        case .start, .restart:
            sync { stats[serverID]?.waitingStart = true; stats[serverID]?.crashed = false }
            appendConsole(serverID, "> \(action.rawValue)")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.sync {
                    self?.stats[serverID]?.waitingStart = false
                    self?.stats[serverID]?.running = true
                    self?.stats[serverID]?.started = MockData.startedString(.now)
                    self?.stats[serverID]?.cpu = 18
                    self?.stats[serverID]?.mem = "2.2GB"
                    self?.stats[serverID]?.memPercent = 27
                }
                self?.appendConsole(serverID, "[\(MockData.consoleTime(.now)) INFO]: Done (8.214s)! For help, type \"help\"")
                try? await Task.sleep(for: .seconds(2))
                self?.sync {
                    if self?.stats[serverID]?.running == true { self?.stats[serverID]?.answersPing = true }
                }
            }
        case .stop, .kill:
            sync {
                stats[serverID]?.running = false
                stats[serverID]?.answersPing = false
                stats[serverID]?.started = nil
                stats[serverID]?.online = 0
                stats[serverID]?.players = []
                stats[serverID]?.cpu = 0
                stats[serverID]?.mem = "0MB"
                stats[serverID]?.memPercent = 0
            }
            appendConsole(serverID, "[\(MockData.consoleTime(.now)) INFO]: Stopping server")
        case .backup:
            let configID = sync { (backupConfigs[serverID] ?? MockData.backupConfigs).first?.id }
            if let configID { addArchive(serverID: serverID, configID: configID) }
        case .clone:
            sync {
                if var copy = servers.first(where: { $0.id == serverID }) {
                    let newID = UUID().uuidString.lowercased()
                    copy = Server(serverID: newID, serverName: copy.serverName + " (Copy)", created: nil, path: nil,
                                  backupPath: nil, executable: copy.executable, logPath: nil,
                                  executionCommand: copy.executionCommand, autoStart: false, autoStartDelay: 10,
                                  crashDetection: copy.crashDetection, stopCommand: copy.stopCommand,
                                  executableUpdateURL: nil, serverIP: copy.serverIP, serverPort: copy.serverPort + 10,
                                  logsDeleteAfter: copy.logsDeleteAfter, type: copy.type)
                    servers.append(copy)
                    stats[newID] = ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20, players: [])
                }
            }
        case .updateExecutable:
            sync { stats[serverID]?.updating = true }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.sync { self?.stats[serverID]?.updating = false }
            }
        }
    }

    func acceptEULA(serverID: String) async throws {
        sync { _ = needsEULA.remove(serverID) }
        try await send(.start, serverID: serverID)
    }

    func sendCommand(_ command: String, serverID: String) async throws {
        try await simulate()
        appendConsole(serverID, "> \(command)")
        let response: String = switch command.split(separator: " ").first.map(String.init) ?? "" {
        case "list":
            "[INFO]: There are \(sync { stats[serverID]?.online ?? 0 }) of a max of 20 players online"
        case "say": "[INFO]: [Server] \(command.dropFirst(4))"
        case "kick": "[INFO]: Kicked \(command.dropFirst(5)) from the game"
        case "op": "[INFO]: Made \(command.dropFirst(3)) a server operator"
        default: "[INFO]: Unknown or incomplete command"
        }
        appendConsole(serverID, response)
    }

    private func appendConsole(_ serverID: String, _ line: String) {
        sync { console[serverID, default: MockData.consoleLines].append(line) }
    }

    /// An hour of plausible values every 30 s, like the panel records them; flat while the server is down.
    func statsHistory(serverID: String) async throws -> [StatSample] {
        try await simulate()
        let current = sync { stats[serverID] }
        guard let current, current.running else { return [] }
        let mem = current.memBytes ?? 0
        return (0..<120).map { i in
            let t = Double(i)
            let wave = sin(t / 9) * 0.5 + sin(t / 3.7) * 0.3
            return StatSample(date: .now.addingTimeInterval(-Double(119 - i) * 30),
                              cpu: max(1, current.cpu + wave * 8),
                              memBytes: max(0, mem * (1 + wave * 0.06)))
        }
    }

    func logs(serverID: String, fromFile: Bool) async throws -> [String] {
        try await simulate()
        return sync { console[serverID] ?? MockData.consoleLines }
    }

    func consoleStream(serverID: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                var seen = 0
                while !Task.isCancelled {
                    let lines = self.sync { self.console[serverID] ?? MockData.consoleLines }
                    for line in lines.dropFirst(seen) { continuation.yield(LogLine(line)) }
                    seen = lines.count
                    try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
                    if self.sync({ self.stats[serverID]?.running == true }) {
                        let now = MockData.consoleTime(.now)
                        self.appendConsole(serverID, "[\(now) " + (MockData.randomLines.randomElement() ?? "[INFO]: tick").dropFirst())
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func updateServer(id: String, changes: ServerConfigPatch) async throws {
        try await simulate()
        sync { if let i = servers.firstIndex(where: { $0.id == id }) { servers[i] = changes.applied(to: servers[i]) } }
    }

    func deleteServer(id: String, deleteFiles: Bool) async throws {
        try await simulate()
        sync { servers.removeAll { $0.id == id }; stats[id] = nil }
    }

    func createServer(_ request: CreateServerRequest) async throws -> String {
        try await Task.sleep(for: .seconds(2)) // simulate downloading the JAR
        let id = UUID().uuidString.lowercased()
        let jar = request.kind == .java ? "\(request.jarType)-\(request.version).jar" : "bedrock_server"
        sync {
            servers.append(MockData.server(id, request.name, jar, port: request.port,
                                           type: request.kind == .java ? .minecraftJava : .minecraftBedrock))
            stats[id] = ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20,
                                    players: [], version: request.version, firstRun: true)
            if request.kind == .java, !request.agreeToEULA { needsEULA.insert(id) }
        }
        return id
    }

    // MARK: Schedules
    func schedules(serverID: String) async throws -> [Schedule]? {
        try await simulate(); return sync { schedules[serverID] ?? MockData.schedules }
    }
    func createSchedule(_ schedule: Schedule, serverID: String) async throws {
        try await simulate()
        sync {
            var list = schedules[serverID] ?? MockData.schedules
            var s = schedule; s.id = (list.map(\.id).max() ?? 0) + 1
            list.append(s); schedules[serverID] = list
        }
    }
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws {
        try await simulate()
        sync {
            var list = schedules[serverID] ?? MockData.schedules
            if let i = list.firstIndex(where: { $0.id == schedule.id }) { list[i] = schedule }
            schedules[serverID] = list
        }
    }
    func deleteSchedule(id: Int, serverID: String) async throws {
        try await simulate()
        sync { var l = schedules[serverID] ?? MockData.schedules; l.removeAll { $0.id == id }; schedules[serverID] = l }
    }

    // MARK: Backups
    func backupConfigs(serverID: String) async throws -> [BackupConfig] {
        try await simulate(); return sync { backupConfigs[serverID] ?? MockData.backupConfigs }
    }
    func saveBackupConfig(_ config: BackupConfig, includeLocation: Bool, serverID: String) async throws {
        try await simulate()
        sync {
            var list = backupConfigs[serverID] ?? MockData.backupConfigs
            var c = config
            if !includeLocation { c.location = list.first(where: \.isDefault)?.location ?? "/crafty/backups/\(serverID)" }
            if let i = list.firstIndex(where: { $0.id == c.id }) { list[i] = c }
            else { c.id = UUID().uuidString.lowercased(); c.isDefault = list.isEmpty; list.append(c) }
            backupConfigs[serverID] = BackupConfig.sorted(list)
        }
    }
    func deleteBackupConfig(id: String, serverID: String) async throws {
        try await simulate()
        try sync {
            var list = backupConfigs[serverID] ?? MockData.backupConfigs
            if list.first(where: { $0.id == id })?.isDefault == true {
                throw CraftyError.server(code: "NOT_ALLOWED", detail: "Cannot delete default backup")
            }
            list.removeAll { $0.id == id }
            backupConfigs[serverID] = list
        }
    }
    func backupFiles(serverID: String, config: BackupConfig) async throws -> [BackupFile]? {
        try await simulate()
        guard config.kind == .zip else { return nil }
        return sync { backups["\(serverID)/\(config.id)"] ?? (config.isDefault ? MockData.backupFiles : []) }
    }
    func startBackup(serverID: String, configID: String) async throws {
        try await simulate()
        addArchive(serverID: serverID, configID: configID)
    }
    /// Ten steps of one latency each, then a good result.
    func backupProgress(serverID: String, idleTimeout: Duration?) -> AsyncStream<BackupProgress> {
        let step = latency
        return AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                for done in 0..<10 {
                    guard (try? await Task.sleep(for: step)) != nil else { return }
                    continuation.yield(.running(Double(done) / 10))
                }
                continuation.yield(.finished(failed: false))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func restoreBackup(_ file: BackupFile, configID: String, inPlace: Bool, serverID: String) async throws {
        try await simulate()
        appendConsole(serverID, "[\(MockData.consoleTime(.now)) INFO]: Restoring backup \(file.name)")
    }
    func deleteBackup(_ file: BackupFile, configID: String, serverID: String) async throws {
        try await simulate()
        sync {
            let key = "\(serverID)/\(configID)"
            let isDefault = (backupConfigs[serverID] ?? MockData.backupConfigs).first { $0.id == configID }?.isDefault == true
            var list = backups[key] ?? (isDefault ? MockData.backupFiles : [])
            list.removeAll { $0 == file }
            backups[key] = list
        }
    }

    private func addArchive(serverID: String, configID: String) {
        guard let file = MockData.backupFile(at: .now) else { return }
        sync {
            let key = "\(serverID)/\(configID)"
            let isDefault = (backupConfigs[serverID] ?? MockData.backupConfigs).first { $0.id == configID }?.isDefault == true
            var list = backups[key] ?? (isDefault ? MockData.backupFiles : [])
            list.removeAll { $0 == file }
            list.insert(file, at: 0)
            backups[key] = list
        }
    }

    // MARK: Files
    func listFiles(serverID: String, path: String) async throws -> [FileEntry] {
        try await simulate()
        return sync {
            let base: [FileEntry] = switch path {
            case "": MockData.rootFiles
            case "plugins": MockData.pluginFiles
            default: []
            }
            let added = createdFolders.filter { ($0 as NSString).deletingLastPathComponent == path }
                .map { FileEntry(name: ($0 as NSString).lastPathComponent, path: $0, isDirectory: true) }
            let uploaded = uploadedFiles.filter { ($0.key as NSString).deletingLastPathComponent == path }
                .map { FileEntry(name: ($0.key as NSString).lastPathComponent, path: $0.key, isDirectory: false,
                                 size: $0.value, modified: nil, canOpen: false) }
            let merged = base.filter { entry in !uploaded.contains { $0.path == entry.path } } + added + uploaded
            return merged.filter { !deletedPaths.contains($0.path) }
                .sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
        }
    }
    func readFile(serverID: String, path: String) async throws -> PanelFile {
        try await simulate()
        return sync { files[path] ?? PanelFile(content: "# \(path)\n# (mock content)\n", modifiedEpoch: 1) }
    }
    func writeFile(serverID: String, path: String, content: String, modifiedEpoch: Double, overwrite: Bool) async throws -> Double {
        try await simulate()
        return try sync {
            let current = files[path]?.modifiedEpoch ?? 1
            if current > modifiedEpoch, !overwrite { throw CraftyError.fileChanged }
            let saved = max(current, modifiedEpoch) + 1
            files[path] = PanelFile(content: content, modifiedEpoch: saved)
            return saved
        }
    }
    func createFolder(serverID: String, parent: String, name: String) async throws {
        guard ServerPath.isValidName(name) else { throw CraftyError.invalidName }
        try await simulate()
        sync {
            let path = ServerPath.join(parent, name)
            deletedPaths.remove(path)
            createdFolders.insert(path)
        }
    }
    func deleteFile(serverID: String, path: String) async throws {
        try await simulate()
        sync { createdFolders.remove(path); uploadedFiles[path] = nil; deletedPaths.insert(path) }
    }
    func uploadFile(serverID: String, folder: String, name: String, from file: URL,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try FileUpload.check(name: name, folder: folder, size: size)
        let total = FileUpload.chunkCount(for: size)
        for index in 0..<total {
            try Task.checkCancellation()
            try await simulate()
            progress(Double(index + 1) / Double(total))
        }
        let mb = Double(size) / 1_048_576
        sync {
            let path = ServerPath.join(folder, name)
            deletedPaths.remove(path)
            uploadedFiles[path] = mb >= 1 ? String(format: "%.1fMB", mb) : String(format: "%.1fKB", Double(size) / 1024)
        }
    }

    // MARK: Webhooks
    func webhooks(serverID: String) async throws -> [Webhook] {
        try await simulate(); return sync { webhooks[serverID] ?? MockData.webhooks }
    }
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws {
        try await simulate()
        sync {
            var l = webhooks[serverID] ?? MockData.webhooks
            if let i = l.firstIndex(where: { $0.id == webhook.id }) { l[i] = webhook }
            else { var w = webhook; w.id = (l.map(\.id).max() ?? 0) + 1; l.append(w) }
            webhooks[serverID] = l
        }
    }
    func deleteWebhook(id: Int, serverID: String) async throws {
        try await simulate()
        sync { var l = webhooks[serverID] ?? MockData.webhooks; l.removeAll { $0.id == id }; webhooks[serverID] = l }
    }
    func testWebhook(id: Int, serverID: String) async throws { try await simulate() }

    // MARK: Users & roles
    func panelAccess() async throws -> PanelAccess { try await simulate(); return sync { grantedAccess } }
    func users() async throws -> [CraftyUser] { try await simulate(); return sync { users } }
    func saveUser(id: Int, changes: UserChanges) async throws {
        try await simulate()
        sync {
            var user = users.first { $0.id == id } ?? CraftyUser.new()
            if user.userID == 0 { user.userID = (users.map(\.userID).max() ?? 0) + 1 }
            if let v = changes.username { user.username = v }
            if let v = changes.enabled { user.enabled = v }
            if let v = changes.superuser { user.superuser = v }
            if let v = changes.lang { user.lang = v }
            if let v = changes.roles { user.roleIDs = v }
            if let i = users.firstIndex(where: { $0.id == user.id }) { users[i] = user } else { users.append(user) }
        }
    }
    func deleteUser(id: Int) async throws { try await simulate(); sync { users.removeAll { $0.id == id } } }
    func roles() async throws -> [Role] { try await simulate(); return sync { roles } }
    func saveRole(_ role: Role) async throws {
        try await simulate()
        sync {
            var r = role
            if let i = roles.firstIndex(where: { $0.id == role.id }) {
                r.servers = role.servers ?? roles[i].servers
                roles[i] = r
            } else {
                r.roleID = (roles.map(\.roleID).max() ?? 0) + 1
                r.servers = role.servers ?? []
                roles.append(r)
            }
        }
    }
    func deleteRole(id: Int) async throws { try await simulate(); sync { roles.removeAll { $0.id == id } } }

    // MARK: Panel
    func hostStats() async throws -> HostStats {
        try await simulate()
        var h = MockData.host
        h.cpuPercent = Double.random(in: 20...45)
        return h
    }
    func announcements() async throws -> [Announcement] { try await simulate(); return sync { announcementList } }
    func clearAnnouncement(id: String) async throws {
        try await simulate(); sync { announcementList.removeAll { $0.id == id } }
    }
}
