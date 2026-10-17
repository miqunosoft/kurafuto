import Foundation

/// Response of `GET /api/v2/servers/{id}/stats`.
/// Crafty returns some numbers as strings ("42.2MB", "5.0"), so decoding is lenient.
struct ServerStats: Codable, Hashable {
    var running: Bool
    var started: String?
    var cpu: Double
    var mem: String
    /// Memory in bytes, when the panel's value can be read as such.
    var memBytes: Double?
    var memPercent: Double
    var worldName: String?
    var worldSize: String?
    var serverPort: Int?
    var online: Int
    var max: Int
    var players: [String]
    var desc: String?
    var icon: String?          // Base64 PNG of the server icon
    var version: String?
    var updating: Bool
    var waitingStart: Bool
    var firstRun: Bool
    var crashed: Bool
    /// The server answered the panel's ping, so players can join. Saved by the panel every 30 s.
    var answersPing: Bool

    enum CodingKeys: String, CodingKey {
        case running, started, cpu, mem
        case memPercent = "mem_percent"
        case worldName = "world_name"
        case worldSize = "world_size"
        case serverPort = "server_port"
        case online, max, players, desc, icon, version, updating
        case waitingStart = "waiting_start"
        case firstRun = "first_run"
        case crashed
        case answersPing = "int_ping_results"
    }

    init(running: Bool, started: String? = nil, cpu: Double, mem: String, memPercent: Double,
         worldName: String? = nil, worldSize: String? = nil, serverPort: Int? = nil,
         online: Int, max: Int, players: [String], desc: String? = nil, icon: String? = nil,
         version: String? = nil, updating: Bool = false, waitingStart: Bool = false,
         firstRun: Bool = false, crashed: Bool = false, answersPing: Bool = false) {
        self.running = running; self.started = started; self.cpu = cpu; self.mem = mem
        self.memBytes = ByteSize.bytes(fromPanelText: mem)
        self.memPercent = memPercent; self.worldName = worldName; self.worldSize = worldSize
        self.serverPort = serverPort; self.online = online; self.max = max; self.players = players
        self.desc = desc; self.icon = icon; self.version = version; self.updating = updating
        self.waitingStart = waitingStart; self.firstRun = firstRun; self.crashed = crashed
        self.answersPing = answersPing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        started = c.lenientString(.started)
        cpu = c.lenientDouble(.cpu)
        // Crafty 4.7 sends a preformatted string ("1.4GB"), 4.11 a byte count. Accept both.
        if let s = try? c.decode(String.self, forKey: .mem) {
            mem = s
            memBytes = ByteSize.bytes(fromPanelText: s)
        } else if let bytes = try? c.decode(Double.self, forKey: .mem), bytes > 0 {
            mem = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
            memBytes = bytes
        } else {
            mem = "0MB"
            memBytes = 0
        }
        memPercent = c.lenientDouble(.memPercent)
        worldName = c.lenientString(.worldName)
        worldSize = c.lenientString(.worldSize)
        serverPort = try? c.decodeIfPresent(Int.self, forKey: .serverPort)
        online = (try? c.decodeIfPresent(Int.self, forKey: .online)) ?? 0
        max = (try? c.decodeIfPresent(Int.self, forKey: .max)) ?? 0
        // "players" arrives either as a JSON string ("[]") or as an array
        if let arr = try? c.decode([String].self, forKey: .players) {
            players = arr
        } else if let s = try? c.decode(String.self, forKey: .players),
                  let data = s.replacingOccurrences(of: "'", with: "\"").data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) {
            players = arr
        } else {
            players = []
        }
        desc = c.lenientString(.desc)
        icon = c.lenientString(.icon)
        version = c.lenientString(.version)
        updating = (try? c.decodeIfPresent(Bool.self, forKey: .updating)) ?? false
        waitingStart = (try? c.decodeIfPresent(Bool.self, forKey: .waitingStart)) ?? false
        firstRun = (try? c.decodeIfPresent(Bool.self, forKey: .firstRun)) ?? false
        crashed = (try? c.decodeIfPresent(Bool.self, forKey: .crashed)) ?? false
        // Stored as text: "True" or "False" (4.7.0, 4.11.0).
        answersPing = (try? c.decode(Bool.self, forKey: .answersPing)) ?? (c.lenientString(.answersPing) == "True")
    }

    var status: ServerStatus {
        if crashed { return .crashed }
        if updating { return .updating }
        if waitingStart { return .starting }
        return running ? .online : .offline
    }
}

extension ServerStats {
    /// Crafty reports `started` as "yyyy-MM-dd HH:mm:ss" in UTC (unlike `created`, which is panel-local).
    static func startTime(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: raw)
    }
}

/// One point of a server's CPU/RAM history.
struct StatSample: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let cpu: Double
    let memBytes: Double
}

/// A row of `GET /api/v2/servers/{id}/history`: the panel's stats of the last hour (recorded every 30 s by
/// default), each with `created` in panel-local time and, wastefully, the whole server row.
struct StatsHistoryRow: Decodable {
    let sample: StatSample?

    enum CodingKeys: String, CodingKey { case created }

    init(from decoder: Decoder) throws {
        let created = try? decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .created)
        let stats = try ServerStats(from: decoder)
        guard let created, let date = Self.date(created) else { sample = nil; return }
        sample = StatSample(date: date, cpu: stats.running ? stats.cpu : 0, memBytes: stats.running ? stats.memBytes ?? 0 : 0)
    }

    /// ISO 8601 without zone, with or without fractional seconds.
    static func date(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(raw.prefix(19)))
    }
}

/// Sizes as the panel formats them: a number and B, KB, MB, GB or TB (1024-based), e.g. "1.4GB" or " 640MB".
enum ByteSize {
    static func bytes(fromPanelText text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard t.hasSuffix("B") else { return Double(t) }
        t.removeLast()
        var factor = 1.0
        if let unit = t.last, let power = ["K", "M", "G", "T"].firstIndex(of: String(unit)) {
            factor = pow(1024, Double(power + 1))
            t.removeLast()
        }
        return Double(t.trimmingCharacters(in: .whitespaces)).map { $0 * factor }
    }
}

enum ServerStatus: String {
    case online, offline, starting, updating, crashed

    var label: String {
        switch self {
        case .online: String(localized: "Online")
        case .offline: String(localized: "Offline")
        case .starting: String(localized: "Starting…")
        case .updating: String(localized: "Updating…")
        case .crashed: String(localized: "Crashed")
        }
    }
}

/// Host values from `/metrics/host` (OpenMetrics text) or dashboard stats.
struct HostStats: Hashable {
    var cpuPercent: Double
    var memPercent: Double
    var diskUsage: [DiskUsage]
    var craftyVersion: String
}

struct DiskUsage: Hashable, Identifiable {
    var id: String { mount }
    var mount: String
    var usedGB: Double
    var totalGB: Double
}

extension KeyedDecodingContainer {
    /// Crafty fills values it does not know yet (stopped server) with Python's `False`,
    /// serialized as the string "False". Those and empty strings become nil.
    func lenientString(_ key: Key) -> String? {
        guard let s = try? decodeIfPresent(String.self, forKey: key), !s.isEmpty, s != "False" else { return nil }
        return s
    }

    func lenientDouble(_ key: Key) -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) {
            let digits = s.filter { "0123456789.".contains($0) }
            return Double(digits) ?? 0
        }
        return 0
    }
}
