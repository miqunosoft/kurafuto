import Foundation

/// Central interface to the Crafty API. The UI ONLY knows this protocol –
/// so everything can be built, tested and previewed with `MockCraftyService`.
protocol CraftyService: AnyObject, Sendable {
    // Auth
    func login(username: String, password: String, totp: String?) async throws -> String
    func invalidateAllSessions() async throws
    func healthCheck() async throws -> Bool

    // Servers
    func servers() async throws -> [Server]
    func server(id: String) async throws -> Server
    func stats(serverID: String) async throws -> ServerStats
    /// CPU and RAM of the last hour, oldest first.
    func statsHistory(serverID: String) async throws -> [StatSample]
    /// Throws `CraftyError.eulaRequired` when the panel refuses to start a Java server without an accepted EULA.
    func send(_ action: ServerAction, serverID: String) async throws
    /// Accepts the Minecraft EULA for a server; the panel starts the server right after.
    func acceptEULA(serverID: String) async throws
    func sendCommand(_ command: String, serverID: String) async throws
    func logs(serverID: String, fromFile: Bool) async throws -> [String]
    /// Sends only the changed fields; see `ServerConfigPatch`.
    func updateServer(id: String, changes: ServerConfigPatch) async throws
    /// `deleteFiles: false` only removes the server from the panel and keeps its folder on disk.
    func deleteServer(id: String, deleteFiles: Bool) async throws
    func createServer(_ request: CreateServerRequest) async throws -> String

    /// Live console. Live implementation: WebSocket `/ws` (undocumented) with fallback to polling `logs`.
    func consoleStream(serverID: String) -> AsyncStream<LogLine>

    // Schedules
    /// Nil when the panel cannot list schedules: Crafty 4.7–4.11 has no list endpoint.
    func schedules(serverID: String) async throws -> [Schedule]?
    func createSchedule(_ schedule: Schedule, serverID: String) async throws
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws
    func deleteSchedule(id: Int, serverID: String) async throws

    // Backups
    /// Default config first.
    func backupConfigs(serverID: String) async throws -> [BackupConfig]
    /// Creates the config when its id is empty. Only superusers may choose the location (`includeLocation`).
    func saveBackupConfig(_ config: BackupConfig, includeLocation: Bool, serverID: String) async throws
    /// Archives stay on the panel. 4.11 also deletes the config's schedules; 4.7 leaves them behind without a target.
    func deleteBackupConfig(id: String, serverID: String) async throws
    /// Nil when the panel cannot list the archives: Crafty 4.7 has no list endpoint, and snapshot configs are never listed.
    func backupFiles(serverID: String, config: BackupConfig) async throws -> [BackupFile]?
    func startBackup(serverID: String, configID: String) async throws
    /// `inPlace` unpacks over the current files; otherwise the panel empties the server folder first.
    func restoreBackup(_ file: BackupFile, configID: String, inPlace: Bool, serverID: String) async throws
    func deleteBackup(_ file: BackupFile, configID: String, serverID: String) async throws

    // Files – paths are relative to the server folder and come from `listFiles`.
    func listFiles(serverID: String, path: String) async throws -> [FileEntry]
    func readFile(serverID: String, path: String) async throws -> PanelFile
    /// Throws `CraftyError.fileChanged` when the file changed on the panel after `modifiedEpoch`, unless `overwrite`.
    /// Returns the new modification time.
    func writeFile(serverID: String, path: String, content: String, modifiedEpoch: Double, overwrite: Bool) async throws -> Double
    /// `name` must pass `ServerPath.isValidName`.
    func createFolder(serverID: String, parent: String, name: String) async throws
    func deleteFile(serverID: String, path: String) async throws
    /// Uploads a local file into `folder` (a path from `listFiles`) as `name`, in chunks; `progress` gets 0...1.
    /// The panel replaces an existing file of that name. Throws when `FileUpload.check` refuses the file.
    func uploadFile(serverID: String, folder: String, name: String, from file: URL,
                    progress: @escaping @Sendable (Double) -> Void) async throws

    // Webhooks
    func webhooks(serverID: String) async throws -> [Webhook]
    /// Creates the webhook when its id is 0.
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws
    func deleteWebhook(id: Int, serverID: String) async throws
    /// The panel sends a test message to the saved webhook; its delivery error comes back as `CraftyError.server`.
    func testWebhook(id: Int, serverID: String) async throws

    // Users & roles (superuser, or USER_CONFIG / ROLES_CONFIG)
    func panelAccess() async throws -> PanelAccess
    /// With roles, last login and IP from each user's detail.
    func users() async throws -> [CraftyUser]
    /// Creates the user when `id` is 0, otherwise sends only the changes.
    func saveUser(id: Int, changes: UserChanges) async throws
    func deleteUser(id: Int) async throws
    /// With each role's servers when the signed-in user may read them (superusers only), else `servers` is nil.
    func roles() async throws -> [Role]
    /// Creates the role when its id is 0.
    func saveRole(_ role: Role) async throws
    func deleteRole(id: Int) async throws

    // Panel
    func hostStats() async throws -> HostStats
    func announcements() async throws -> [Announcement]
    func clearAnnouncement(id: String) async throws
}

enum CraftyError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden(String)
    case server(code: String, detail: String?)
    case decoding(Error)
    case transport(Error)
    case untrustedCertificate(sha256: String)
    case notSupportedByPanelVersion(String)
    case eulaRequired
    case fileChanged
    case invalidName
    case uploadRefused(String)
    case redirected

    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "Invalid address.")
        case .unauthorized: String(localized: "Session expired. Please sign in again.")
        case .forbidden(let what): String(localized: "Permission denied: \(what)")
        case .server(let code, let detail):
            detail.map { String(localized: "Panel error \(code): \($0)") } ?? String(localized: "Panel error \(code)")
        case .decoding(let e): String(localized: "Could not read response: \(e.localizedDescription)")
        case .transport(let e): String(localized: "Connection failed: \(e.localizedDescription)")
        case .untrustedCertificate: String(localized: "The certificate is self-signed. Verify the fingerprint and trust it?")
        case .notSupportedByPanelVersion(let f): String(localized: "\(f) is not supported by this panel version.")
        case .eulaRequired: String(localized: "The Minecraft EULA must be accepted before this server can start.")
        case .fileChanged: String(localized: "The file was changed on the panel after you opened it.")
        case .uploadRefused(let reason): reason
        case .redirected: String(localized: "The panel redirected to another address. Kurafuto only connects to the address you added.")
        case .invalidName: String(localized: "Names cannot be empty, \".\" or \"..\" and cannot contain / or \\.")
        }
    }
}

/// What went wrong, as far as the user can act on it.
enum PanelProblem: Equatable {
    case offline, sessionExpired, permissionDenied, other
}

extension Error {
    var panelProblem: PanelProblem {
        switch self as? CraftyError {
        case .unauthorized: return .sessionExpired
        case .forbidden: return .permissionDenied
        case .transport(let underlying): return underlying.isOffline ? .offline : .other
        default: return isOffline ? .offline : .other
        }
    }

    private var isOffline: Bool {
        guard let code = (self as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed].contains(code)
    }
}
