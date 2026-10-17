import CryptoKit
import Foundation

/// Body of `POST /api/v2/auth/login`. `totp` must be left out when empty:
/// Crafty 4.11 rejects `"totp": null` as incorrect credentials.
struct LoginRequest: Encodable {
    let username: String
    let password: String
    let totp: String?
}

/// Real implementation against Crafty Controller 4 (API v2).
///
/// ✅ = documented in the official openapi-spec.yml
/// ⚠️ = exists in the panel (used by the web UI) but NOT in the spec → verify against the source
///      (gitlab.com/crafty-controller/crafty-4, app/classes/web/routes/api) and adjust paths if needed.
final class LiveCraftyService: CraftyService, @unchecked Sendable {
    let client: APIClient

    init(client: APIClient) { self.client = client }

    private typealias Empty = APIClient.Empty

    // MARK: Auth ✅
    func login(username: String, password: String, totp: String?) async throws -> String {
        struct Res: Decodable { let token: String }
        let res: Res = try await client.request(.post, "/api/v2/auth/login",
                                                body: .json(LoginRequest(username: username, password: password, totp: totp)))
        client.token = res.token
        return res.token
    }
    func invalidateAllSessions() async throws {
        let _: Empty = try await client.request(.post, "/api/v2/auth/invalidate_tokens")
    }
    func healthCheck() async throws -> Bool {
        let _: Empty = try await client.request(.get, "/api/v2/crafty/check"); return true
    }

    // MARK: Servers ✅
    func servers() async throws -> [Server] { try await client.request(.get, "/api/v2/servers") }
    func server(id: String) async throws -> Server { try await client.request(.get, "/api/v2/servers/\(id)") }
    func stats(serverID: String) async throws -> ServerStats { try await client.request(.get, "/api/v2/servers/\(serverID)/stats") }
    /// ⚠️ Not in the spec; route from the panel source (`history.py`), verified on 4.7.0 and 4.11.0.
    func statsHistory(serverID: String) async throws -> [StatSample] {
        let rows: [StatsHistoryRow] = try await client.request(.get, "/api/v2/servers/\(serverID)/history")
        return rows.compactMap(\.sample).sorted { $0.date < $1.date }
    }

    func send(_ action: ServerAction, serverID: String) async throws {
        // Without a config id, 4.7.0 answers ok but the backup fails inside the panel.
        if action == .backup, let config = try? await backupConfigs(serverID: serverID).first {
            return try await startBackup(serverID: serverID, configID: config.id)
        }
        // Crafty answers start_server with ok and reports a missing EULA only over the WebSocket, so the socket
        // has to be connected (answered a ping) before the request goes out.
        guard action == .start,
              let socket = try? client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: serverID)) else {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/\(action.rawValue)")
            return
        }
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        let connected = await Self.ping(socket)
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/\(action.rawValue)")
        if connected, await Self.panelAsksForEULA(socket, serverID: serverID) { throw CraftyError.eulaRequired }
    }
    func acceptEULA(serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/eula")
    }

    /// The panel's command queue polls once per second, so the EULA request arrives within about two seconds.
    /// Console output from the server means it is starting and ends the wait early.
    private static func panelAsksForEULA(_ socket: URLSessionWebSocketTask, serverID: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                while let text = try? await receive(from: socket) {
                    if CraftyConsoleFeed.eulaRequest(fromSocketMessage: text) == serverID { return true }
                    if !CraftyConsoleFeed.lines(fromSocketMessage: text).isEmpty { return false }
                }
                return false
            }
            group.addTask { try? await Task.sleep(for: .seconds(4)); return false }
            let asked = await group.next() ?? false
            group.cancelAll()
            return asked
        }
    }
    func sendCommand(_ command: String, serverID: String) async throws {
        // Per docs: send without the leading slash.
        let cmd = command.hasPrefix("/") ? String(command.dropFirst()) : command
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/stdin", body: .text(cmd))
    }
    func logs(serverID: String, fromFile: Bool) async throws -> [String] {
        let lines: [String] = try await client.request(.get, "/api/v2/servers/\(serverID)/logs",
                                                       query: [URLQueryItem(name: "file", value: fromFile ? "true" : "false")])
        return lines.map(\.unescapingCraftyLogHTML)
    }
    func updateServer(id: String, changes: ServerConfigPatch) async throws {
        guard !changes.isEmpty else { return }
        let _: Empty = try await client.request(.patch, "/api/v2/servers/\(id)", body: .json(changes))
    }
    func deleteServer(id: String, deleteFiles: Bool) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(id)",
                                                query: deleteFiles ? [URLQueryItem(name: "files", value: "true")] : [])
    }
    func createServer(_ request: CreateServerRequest) async throws -> String {
        struct Res: Decodable { let new_server_id: String }
        let r: Res = try await client.request(.post, "/api/v2/servers", body: .json(request))
        return r.new_server_id
    }

    /// Backlog from `/logs`, then new lines over the panel WebSocket `/ws` ⚠️ (undocumented; see
    /// `CraftyConsoleFeed`). If the socket is refused, drops or stops answering pings, the stream keeps
    /// going by polling `/logs`.
    func consoleStream(serverID: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let task = Task {
                var shown = (try? await self.logs(serverID: serverID, fromFile: false)) ?? []
                shown.forEach { continuation.yield(LogLine($0)) }

                if let socket = try? self.client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: serverID)) {
                    socket.resume()
                    let keepAlive = Task { await Self.keepAlive(socket) }
                    while !Task.isCancelled, let message = try? await Self.receive(from: socket) {
                        let lines = CraftyConsoleFeed.lines(fromSocketMessage: message)
                        lines.forEach { continuation.yield(LogLine($0)) }
                        shown = CraftyConsoleFeed.remember(lines, after: shown)
                    }
                    keepAlive.cancel()
                    socket.cancel(with: .goingAway, reason: nil)
                }

                while !Task.isCancelled {
                    if let current = try? await self.logs(serverID: serverID, fromFile: false) {
                        CraftyConsoleFeed.newLines(after: shown, in: current).forEach { continuation.yield(LogLine($0)) }
                        shown = current
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func receive(from socket: URLSessionWebSocketTask) async throws -> String {
        let message = try await withTaskCancellationHandler {
            try await socket.receive()
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
        switch message {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    /// Progress from the panel WebSocket `/ws` ⚠️ (same subscription as the console). After the last event the panel
    /// stores the result in the config's `status`, which only `GET …/backups/backup/{id}` returns.
    func backupProgress(serverID: String, idleTimeout: Duration?) -> AsyncStream<BackupProgress> {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                guard let socket = try? self.client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: serverID)) else { return }
                socket.resume()
                let keepAlive = Task { await Self.keepAlive(socket) }
                defer {
                    keepAlive.cancel()
                    socket.cancel(with: .goingAway, reason: nil)
                }
                var deadline = idleTimeout.map { ContinuousClock.now + $0 }
                while !Task.isCancelled, let message = try? await Self.receive(from: socket, until: deadline) {
                    guard let event = CraftyConsoleFeed.backupStatus(fromSocketMessage: message) else { continue }
                    deadline = idleTimeout.map { ContinuousClock.now + $0 }
                    guard event.percent >= 100 else {
                        continuation.yield(.running(event.percent / 100))
                        continue
                    }
                    try? await Task.sleep(for: .seconds(2))
                    continuation.yield(.finished(failed: await self.lastBackupFailed(serverID: serverID, configID: event.backupID)))
                    return
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func lastBackupFailed(serverID: String, configID: String?) async -> Bool? {
        struct Config: Decodable { let status: String }
        guard let configID, BackupConfig.isValidID(configID),
              let config: Config = try? await client.requestUnwrapped(.get, "/api/v2/servers/\(serverID)/backups/backup/\(configID)")
        else { return nil }
        return BackupConfig.lastRunFailed(status: config.status)
    }

    /// `receive` that gives up at `deadline`, cancelling the socket.
    private static func receive(from socket: URLSessionWebSocketTask, until deadline: ContinuousClock.Instant?) async throws -> String {
        guard let deadline else { return try await receive(from: socket) }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await receive(from: socket) }
            group.addTask {
                try await Task.sleep(until: deadline, clock: .continuous)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    /// Crafty stays silent while a server is idle, so a dead connection only shows up through pings.
    private static func keepAlive(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, await ping(socket) else { return }
        }
    }

    /// True when the panel answered within the timeout. A ping is only sent after the handshake, so a pong
    /// also means the socket is connected. On timeout the socket is cancelled.
    private static func ping(_ socket: URLSessionWebSocketTask, timeout: Duration = .seconds(10)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { done in socket.sendPing { done.resume(returning: $0 == nil) } }
            }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let first = await group.next() ?? false
            // Cancelling the socket also completes a pending ping, so the group can finish.
            if !first { socket.cancel(with: .goingAway, reason: nil) }
            group.cancelAll()
            return first
        }
    }

    // MARK: Schedules ✅ create/update/delete
    /// Crafty 4.7–4.11 cannot list schedules: `GET …/tasks` is an empty stub that answers 500, and
    /// `POST …/tasks` returns no id for disabled or chained schedules. Only the web panel lists them.
    func schedules(serverID: String) async throws -> [Schedule]? { nil }
    func createSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/tasks", body: .json(schedule))
    }
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.patch, "/api/v2/servers/\(serverID)/tasks/\(schedule.id)", body: .json(schedule))
    }
    func deleteSchedule(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/tasks/\(id)")
    }

    // MARK: Backups ✅ (routes from the panel source, verified on 4.7.0 and 4.11.0)
    /// Answers without the envelope: an object keyed by backup id.
    func backupConfigs(serverID: String) async throws -> [BackupConfig] {
        let configs: [String: BackupConfig] = try await client.requestUnwrapped(.get, "/api/v2/servers/\(serverID)/backups")
        return BackupConfig.sorted(configs.values)
    }
    func saveBackupConfig(_ config: BackupConfig, includeLocation: Bool, serverID: String) async throws {
        let body = BackupConfigBody(config: config, includeLocation: includeLocation)
        if config.id.isEmpty {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/backups", body: .json(body))
        } else {
            let _: Empty = try await client.request(.patch, try Self.backupPath(serverID, config.id), body: .json(body))
        }
    }
    func deleteBackupConfig(id: String, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, try Self.backupPath(serverID, id))
    }
    /// `GET …/files` exists since 4.11 and lists only `*.zip` paths; 4.7 answers 405.
    func backupFiles(serverID: String, config: BackupConfig) async throws -> [BackupFile]? {
        guard config.kind == .zip else { return nil }
        struct Res: Decodable { let backups: [String] }
        do {
            let res: Res = try await client.requestUnwrapped(.get, try Self.backupPath(serverID, config.id) + "/files")
            return BackupFile.list(fromPaths: res.backups)
        } catch CraftyError.server(code: "METHOD_NOT_ALLOWED", _) {
            return nil
        }
    }
    func startBackup(serverID: String, configID: String) async throws {
        guard BackupConfig.isValidID(configID) else { throw CraftyError.invalidURL }
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/backup_server/\(configID)")
    }
    func restoreBackup(_ file: BackupFile, configID: String, inPlace: Bool, serverID: String) async throws {
        struct Body: Encodable { let filename: String; let inPlace: Bool }
        let _: Empty = try await client.request(.post, try Self.backupPath(serverID, configID),
                                                body: .json(Body(filename: file.name, inPlace: inPlace)))
    }
    func deleteBackup(_ file: BackupFile, configID: String, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, try Self.backupPath(serverID, configID) + "/files",
                                                body: .json(["filename": file.name]))
    }

    private static func backupPath(_ serverID: String, _ configID: String) throws -> String {
        guard BackupConfig.isValidID(configID) else { throw CraftyError.invalidURL }
        return "/api/v2/servers/\(serverID)/backups/backup/\(configID)"
    }

    // MARK: Files ✅ (routes from the panel source, verified on 4.7.0 and 4.11.0)
    // Never copy/move: those had a path traversal in 4.7.0 (issue #660).
    func listFiles(serverID: String, path: String) async throws -> [FileEntry] {
        let listing: FolderListing = try await client.request(.post, "/api/v2/servers/\(serverID)/files",
                                                              body: .json(["path": path]))
        return listing.entries
    }
    func readFile(serverID: String, path: String) async throws -> PanelFile {
        try await client.request(.post, "/api/v2/servers/\(serverID)/files", body: .json(["path": path]))
    }
    func writeFile(serverID: String, path: String, content: String, modifiedEpoch: Double, overwrite: Bool) async throws -> Double {
        struct Body: Encodable {
            let path: String, contents: String, modified_epoch: Double, overwrite: Bool
        }
        struct Res: Decodable {
            struct Attributes: Decodable { let modified_epoch: Double }
            let attributes: Attributes
        }
        do {
            let res: Res = try await client.request(.patch, "/api/v2/servers/\(serverID)/files",
                                                    body: .json(Body(path: path, contents: content, modified_epoch: modifiedEpoch,
                                                                     overwrite: overwrite)))
            return res.attributes.modified_epoch
        } catch CraftyError.server(code: "409", _) {
            throw CraftyError.fileChanged
        }
    }
    func createFolder(serverID: String, parent: String, name: String) async throws {
        guard ServerPath.isValidName(name) else { throw CraftyError.invalidName }
        struct Body: Encodable { let parent: String, name: String, directory: Bool }
        let _: Empty = try await client.request(.put, "/api/v2/servers/\(serverID)/files/create",
                                                body: .json(Body(parent: parent, name: name, directory: true)))
    }
    /// Same protocol as the web panel's `upload.js` (4.7.0 and 4.11.0): an empty first request announces the
    /// file, then every chunk carries its index and SHA-256; the panel joins them after the last one.
    func uploadFile(serverID: String, folder: String, name: String, from file: URL,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try FileUpload.check(name: name, folder: folder, size: size)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let path = "/api/v2/servers/\(serverID)/files/upload"
        let total = FileUpload.chunkCount(for: size)
        var headers = ["chunked": "true", "fileSize": "\(size)", "totalChunks": "\(total)",
                       "fileName": name, "location": folder, "fileId": UUID().uuidString.lowercased()]
        _ = try await client.upload(path, headers: headers, body: nil)
        for index in 0..<total {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: FileUpload.chunkBytes), !chunk.isEmpty else {
                throw CraftyError.uploadRefused(String(localized: "The file changed while it was being uploaded."))
            }
            headers["chunkId"] = "\(index)"
            headers["chunkHash"] = SHA256.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
            let status = try await client.upload(path, headers: headers, body: chunk)
            progress(Double(index + 1) / Double(total))
            if index == total - 1, status != "completed" {
                throw CraftyError.server(code: "UPLOAD_INCOMPLETE", detail: status)
            }
        }
    }
    func deleteFile(serverID: String, path: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/files",
                                                body: .json(["file_system_objects": [["filename": path]]]))
    }

    // MARK: Webhooks ✅ (the spec's singular `/server/{id}/webhook/{wid}` does not exist; the panel routes `/servers/`)
    func webhooks(serverID: String) async throws -> [Webhook] {
        let rows: [String: WebhookRow] = try await client.request(.get, "/api/v2/servers/\(serverID)/webhook")
        return WebhookRow.list(rows)
    }
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws {
        if webhook.id == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/webhook", body: .json(WebhookBody(webhook: webhook)))
        } else {
            let _: Empty = try await client.request(.patch, "/api/v2/servers/\(serverID)/webhook/\(webhook.id)",
                                                    body: .json(WebhookBody(webhook: webhook)))
        }
    }
    func deleteWebhook(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/webhook/\(id)")
    }
    func testWebhook(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/webhook/\(id)")
    }

    // MARK: Users & roles ✅
    func panelAccess() async throws -> PanelAccess {
        struct Me: Decodable {
            let userID: Int?
            let superuser: Bool
            enum CodingKeys: String, CodingKey { case userID = "user_id", superuser }
        }
        async let me: Me = client.request(.get, "/api/v2/users/@me")
        async let permissions: CraftyPermissions = client.request(.get, "/api/v2/users/@me/permissions")
        let (user, rights) = try await (me, permissions)
        return PanelAccess(isSuperuser: user.superuser, permissions: rights, userID: user.userID)
    }
    /// The list has no roles; each user's detail has them.
    func users() async throws -> [CraftyUser] {
        let list: [CraftyUser] = try await client.request(.get, "/api/v2/users")
        let client = client
        return try await withThrowingTaskGroup(of: CraftyUser.self) { group in
            for user in list {
                group.addTask { try await client.request(.get, "/api/v2/users/\(user.userID)") }
            }
            var detailed: [CraftyUser] = []
            for try await user in group { detailed.append(user) }
            return detailed.sorted { $0.userID < $1.userID }
        }
    }
    func saveUser(id: Int, changes: UserChanges) async throws {
        if id == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/users", body: .json(changes))
        } else if !changes.isEmpty {
            let _: Empty = try await client.request(.patch, "/api/v2/users/\(id)", body: .json(changes))
        }
    }
    func deleteUser(id: Int) async throws { let _: Empty = try await client.request(.delete, "/api/v2/users/\(id)") }
    /// Role servers are superuser-only; for everyone else the roles come without them.
    func roles() async throws -> [Role] {
        let list: [Role] = try await client.request(.get, "/api/v2/roles")
        let client = client
        do {
            return try await withThrowingTaskGroup(of: Role.self) { group in
                for role in list {
                    group.addTask {
                        var r = role
                        r.servers = try await client.request(.get, "/api/v2/roles/\(role.roleID)/servers")
                        return r
                    }
                }
                var detailed: [Role] = []
                for try await role in group { detailed.append(role) }
                return detailed.sorted { $0.roleID < $1.roleID }
            }
        } catch CraftyError.forbidden {
            return list.sorted { $0.roleID < $1.roleID }
        }
    }
    func saveRole(_ role: Role) async throws {
        if role.roleID == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/roles", body: .json(RoleBody(role: role)))
        } else {
            let _: Empty = try await client.request(.patch, "/api/v2/roles/\(role.roleID)", body: .json(RoleBody(role: role)))
        }
    }
    func deleteRole(id: Int) async throws { let _: Empty = try await client.request(.delete, "/api/v2/roles/\(id)") }

    // MARK: Panel ✅
    func hostStats() async throws -> HostStats {
        let text = try await client.rawText("/metrics/host")
        let m = OpenMetricsParser.parse(text)
        return HostStats(cpuPercent: m["CPU_Usage"] ?? 0, memPercent: m["Mem_Usage"] ?? 0, diskUsage: [], craftyVersion: "?")
    }
    func announcements() async throws -> [Announcement] { try await client.request(.get, "/api/v2/crafty/announcements") }
    func clearAnnouncement(id: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/crafty/announcements", body: .json(["id": id]))
    }
}

enum OpenMetricsParser {
    /// Minimal parser: "Name{labels} 1.23" → [Name: 1.23]
    static func parse(_ text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let v = Double(parts[parts.count - 1]) else { continue }
            let name = parts[0].split(separator: "{").first.map(String.init) ?? String(parts[0])
            out[name] = v
        }
        return out
    }
}
