import Foundation

/// Realistic sample data – modeled after the examples in the Crafty OpenAPI spec.
enum MockData {
    static let survivalID = "5adcec83-684c-4555-a7e9-9d913203d07e"
    static let creativeID = "f53b7b9d-48cc-40f1-89ce-331bda9458ba"
    static let bedrockID = "54d4cbb0-2a2b-4529-9e72-4682ebcb9330"
    static let modpackID = "ef3fb2d1-a94c-4d9b-8c65-c4274be706cb"

    static func server(_ id: String, _ name: String, _ jar: String, port: Int, type: ServerType = .minecraftJava) -> Server {
        Server(serverID: id, serverName: name, created: "2025-05-18T22:36:04",
               path: "/crafty/servers/\(id)", backupPath: "/crafty/backups/\(id)",
               executable: jar, logPath: "/crafty/servers/\(id)/logs/latest.log",
               executionCommand: "java -Xms2G -Xmx4G -jar \(jar) nogui",
               autoStart: true, autoStartDelay: 10, crashDetection: true, stopCommand: "stop",
               executableUpdateURL: nil, serverIP: "127.0.0.1", serverPort: port,
               logsDeleteAfter: 7, type: type, shutdownTimeout: 60, ignoredExits: "0", countPlayers: true,
               showStatus: true)
    }

    static let servers: [Server] = [
        server(survivalID, "Survival SMP", "paper-1.21.4.jar", port: 25565),
        server(creativeID, "Creative World", "purpur-1.21.4.jar", port: 25566),
        server(bedrockID, "Bedrock Friends", "bedrock_server", port: 19132, type: .minecraftBedrock),
        server(modpackID, "ATM10 Modpack", "neoforge-21.1.jar", port: 25567),
    ]

    // Demo times follow the clock, so the demo never shows a start time in the future or a days-old uptime.
    private static let survivalStart = Date.now.addingTimeInterval(-(2 * 3600 + 12 * 60))

    /// Crafty's `started` format: UTC, `yyyy-MM-dd HH:mm:ss` (see `ServerStats.startTime`).
    static func startedString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// Console timestamp as Minecraft prints it: local time, 24 h, independent of the device locale.
    static func consoleTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static let stats: [String: ServerStats] = [
        survivalID: ServerStats(running: true, started: startedString(survivalStart), cpu: 23.4, mem: "3.1GB", memPercent: 38,
                                worldName: "world", worldSize: "2.4GB", serverPort: 25565, online: 4, max: 20,
                                players: ["Steve_DE", "miquno", "Alex2010", "MasterBuilder"],
                                desc: "§aWelcome to the SMP!", version: "Paper 1.21.4", answersPing: true),
        creativeID: ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, worldName: "creative",
                                worldSize: "512MB", serverPort: 25566, online: 0, max: 10, players: [],
                                desc: "Creative", version: "Purpur 1.21.4"),
        bedrockID: ServerStats(running: true, started: startedString(.now.addingTimeInterval(-(27 * 3600 + 18 * 60))), cpu: 6.2, mem: "640MB", memPercent: 8,
                               worldName: "Bedrock level", worldSize: "180MB", serverPort: 19132, online: 1, max: 10,
                               players: ["PocketHero"], version: "1.21.40", answersPing: true),
        modpackID: ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, worldName: "world", worldSize: "6.8GB",
                               serverPort: 25567, online: 0, max: 8, players: [], version: "NeoForge 1.21.1", crashed: true),
    ]

    static let consoleLines: [String] = {
        let start = survivalStart, now = Date.now
        let lines: [(Date, String)] = [
            (start, "INFO]: Starting minecraft server version 1.21.4"),
            (start, "INFO]: Loading properties"),
            (start + 1, "INFO]: Default game type: SURVIVAL"),
            (start + 6, "INFO]: Preparing level \"world\""),
            (start + 12, "INFO]: Done (11.832s)! For help, type \"help\""),
            (now - 754, "INFO]: Steve_DE joined the game"),
            (now - 733, "INFO]: <Steve_DE> hey everyone"),
            (now - 478, "WARN]: Can't keep up! Is the server overloaded? Running 2140ms behind"),
            (now - 80, "INFO]: miquno joined the game"),
            (now - 65, "INFO]: <miquno> who set my house on fire 😅"),
        ]
        return lines.map { "[\(consoleTime($0.0)) \($0.1)" }
    }()

    static let randomLines: [String] = [
        "[INFO]: Saving the game (this may take a moment!)",
        "[INFO]: Saved the game",
        "[INFO]: <Alex2010> anyone got diamonds?",
        "[INFO]: MasterBuilder has made the advancement [Stone Age]",
        "[WARN]: Steve_DE moved too quickly! 12.4,0.0,3.1",
    ]

    static let schedules: [Schedule] = [
        Schedule(id: 1, name: "Nightly restart", enabled: true, action: .restart, interval: 1, intervalType: .days,
                 startTime: "04:00", command: nil, parent: nil, oneTime: false, cronString: nil, delay: 0,
                 nextRun: .now.addingTimeInterval(9 * 3600)),
        Schedule(id: 2, name: "Hourly save", enabled: true, action: .command, interval: 1, intervalType: .hours,
                 command: "save-all", parent: nil, oneTime: false, cronString: nil, delay: 0,
                 nextRun: .now.addingTimeInterval(35 * 60)),
        Schedule(id: 3, name: "Welcome back", enabled: true, action: .command, interval: 0, intervalType: .reaction,
                 command: "say The server is back!", parent: 1, oneTime: false, cronString: nil, delay: 120, nextRun: nil),
        Schedule(id: 4, name: "Weekend event", enabled: false, action: .command, interval: 0, intervalType: .cron,
                 command: "say Double XP is active!", parent: nil, oneTime: false, cronString: "0 18 * * 6", delay: 0, nextRun: nil),
    ]

    static let defaultBackupID = "6f1c2a7e-3b4d-4e5f-8a9b-0c1d2e3f4a5b"

    static let backupConfigs: [BackupConfig] = [
        BackupConfig(id: defaultBackupID, name: "Default Backup", location: "/crafty/backups/\(survivalID)",
                     maxBackups: 10, compress: true, beforeCommand: "save-off", afterCommand: "save-on",
                     excludedPaths: ["logs", "cache"], isDefault: true),
        BackupConfig(id: "9d8e7f6a-5b4c-4d3e-9f2a-1b0c9d8e7f6a", name: "NAS copy", location: "/mnt/nas/minecraft",
                     maxBackups: 30, compress: true, shutdown: true),
    ]

    /// Archives every six hours, named the way the panel names them.
    static var backupFiles: [BackupFile] {
        (0..<6).compactMap { backupFile(at: .now.addingTimeInterval(Double(-6 * $0) * 3600)) }
    }

    /// The panel names archives after its local wall-clock time; the demo panel runs in the device's time zone.
    static func backupFile(at date: Date) -> BackupFile? {
        let local = BackupFile.nameFormat()
        local.timeZone = .current
        return BackupFile(path: "/crafty/backups/\(survivalID)/\(local.string(from: date)).zip")
    }

    static let rootFiles: [FileEntry] = [
        FileEntry(name: "logs", path: "logs", isDirectory: true, modified: "2026/10/14 20:17"),
        FileEntry(name: "plugins", path: "plugins", isDirectory: true, modified: "2026/10/12 18:40"),
        FileEntry(name: "world", path: "world", isDirectory: true, modified: "2026/10/15 09:58"),
        FileEntry(name: "world_nether", path: "world_nether", isDirectory: true, modified: "2026/10/15 09:58"),
        FileEntry(name: "eula.txt", path: "eula.txt", isDirectory: false, size: "158.0B", modified: "2026/05/18 19:02", canOpen: true),
        FileEntry(name: "ops.json", path: "ops.json", isDirectory: false, size: "210.0B", modified: "2026/09/30 21:15", canOpen: true),
        FileEntry(name: "paper-1.21.4.jar", path: "paper-1.21.4.jar", isDirectory: false, size: "48.8MB", modified: "2026/10/01 08:00", canOpen: false),
        FileEntry(name: "server.properties", path: "server.properties", isDirectory: false, size: "1.4KB", modified: "2026/10/14 20:17", canOpen: true),
        FileEntry(name: "whitelist.json", path: "whitelist.json", isDirectory: false, size: "340.0B", modified: "2026/10/02 17:30", canOpen: true),
    ]

    static let pluginFiles: [FileEntry] = [
        FileEntry(name: "Essentials", path: "plugins/Essentials", isDirectory: true, modified: "2026/10/12 18:40"),
        FileEntry(name: "EssentialsX.jar", path: "plugins/EssentialsX.jar", isDirectory: false, size: "3.0MB", modified: "2026/10/12 18:39", canOpen: false),
        FileEntry(name: "LuckPerms.jar", path: "plugins/LuckPerms.jar", isDirectory: false, size: "2.1MB", modified: "2026/10/12 18:39", canOpen: false),
    ]

    static let serverProperties = """
    #Minecraft server properties
    motd=\\u00A7aWelcome to the SMP!
    difficulty=normal
    gamemode=survival
    max-players=20
    online-mode=true
    pvp=true
    server-port=25565
    spawn-protection=16
    view-distance=10
    simulation-distance=8
    white-list=true
    enable-command-block=false
    """

    static let webhooks: [Webhook] = [
        Webhook(id: 1, type: "Discord", name: "Discord #server-status", url: "https://discord.com/api/webhooks/1/example",
                botName: "Server Bot", triggers: ["start_server", "stop_server", "crash_detected"],
                body: "{{ server_name }}: {{ event_type }}", color: "#5865f2", enabled: true),
        Webhook(id: 2, type: "Mattermost", name: "Backup log", url: "http://chat.home.example:8065/hooks/example",
                botName: "Backup", triggers: ["backup_server"],
                body: "Backup {{ backup_name }} ({{ backup_size }}) {{ backup_status }}", color: "#005cd1", enabled: false),
    ]

    static let users: [CraftyUser] = [
        CraftyUser(userID: 1, username: "admin", enabled: true, superuser: true, lang: "en_EN",
                   created: "05/18/2025", lastLogin: "2026-10-14T08:10:00", lastIP: "192.168.1.42", roleIDs: []),
        CraftyUser(userID: 2, username: "steve", enabled: true, superuser: false, lang: "de_DE",
                   created: "06/02/2025", lastLogin: "2026-10-12T20:01:00", lastIP: "10.0.0.7", roleIDs: [1]),
        CraftyUser(userID: 3, username: "alex", enabled: false, superuser: false, lang: "en_EN",
                   created: "07/21/2025", lastLogin: nil, lastIP: nil, roleIDs: [2]),
    ]

    static let roles: [Role] = [
        Role(roleID: 1, roleName: "Moderator", manager: 1, mfaRequired: true, servers: [
            RoleServerPermission(serverID: survivalID, permissions: "11100001"),
            RoleServerPermission(serverID: creativeID, permissions: "11100001"),
        ]),
        Role(roleID: 2, roleName: "View only", manager: 1, mfaRequired: false, servers: [
            RoleServerPermission(serverID: survivalID, permissions: "00100000"),
        ]),
    ]

    static let announcements: [Announcement] = [
        Announcement(id: "dbc0c2aa-690a-46c3-aa67-db8e3bde0cd0", date: "2026/10/01",
                     title: "New panel version available", desc: "An update for your panel has been released.", link: nil),
    ]

    static let host = HostStats(cpuPercent: 31.5, memPercent: 63.8,
                                diskUsage: [DiskUsage(mount: "/", usedGB: 182, totalGB: 476),
                                            DiskUsage(mount: "/mnt/nas", usedGB: 1_840, totalGB: 3_600)],
                                craftyVersion: "4.7.2")

    static let instance = Instance(name: "Homelab", baseURL: URL(string: "https://192.168.1.20:8443") ?? URL(filePath: "/"),
                                   username: "admin", authMethod: .password)
}
