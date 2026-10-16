import Foundation

/// Pure parsing for the live console: messages from the panel WebSocket and the polled `/logs` buffer.
/// Protocol ported from Crafty's `websocket_handler.py` and `ServerOutBuf.new_line_handler` (4.7.0, 4.11.0).
enum CraftyConsoleFeed {
    /// Upper bound for remembered lines, so diffing stays cheap and memory stays flat.
    static let memory = 1000

    /// Query that subscribes the socket to one server's console, like the web panel's server page.
    static func socketQuery(serverID: String) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: "/panel/server_detail"),
         URLQueryItem(name: "page_query_params", value: "?id=\(serverID)")]
    }

    /// Console lines in a `{"event":"vterm_new_line","data":{"line":"…<br />"}}` message.
    /// Other events and malformed messages yield nothing.
    static func lines(fromSocketMessage text: String) -> [String] {
        struct Event: Decodable { let event: String }
        struct NewLine: Decodable {
            struct Payload: Decodable { let line: String }
            let data: Payload
        }
        let json = Data(text.utf8)
        guard (try? JSONDecoder().decode(Event.self, from: json))?.event == "vterm_new_line",
              let html = (try? JSONDecoder().decode(NewLine.self, from: json))?.data.line else { return [] }
        return plainLines(fromHTML: html)
    }

    /// Server ID in `{"event":"send_eula_bootbox","data":{"id":"…"}}`: the panel refused to start a Java server
    /// because its EULA is not accepted. Sent to all sockets of the user who pressed start.
    static func eulaRequest(fromSocketMessage text: String) -> String? {
        struct Request: Decodable {
            struct Payload: Decodable { let id: String }
            let event: String
            let data: Payload
        }
        guard let request = try? JSONDecoder().decode(Request.self, from: Data(text.utf8)),
              request.event == "send_eula_bootbox" else { return nil }
        return request.data.id
    }

    /// Progress in `{"event":"backup_status","data":{"percent":42.5,"total_files":"1.2GB","backup_id":"…"}}`, sent to the
    /// server page for every archived file. Percent is 0...100; 100 also ends a failed backup. The first event has
    /// no `backup_id`.
    static func backupStatus(fromSocketMessage text: String) -> (percent: Double, backupID: String?)? {
        struct Status: Decodable {
            struct Payload: Decodable {
                let percent: Double
                let backup_id: String?
            }
            let event: String
            let data: Payload
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: Data(text.utf8)),
              status.event == "backup_status", status.data.percent.isFinite else { return nil }
        return (min(max(status.data.percent, 0), 100), status.data.backup_id)
    }

    /// Crafty escapes the raw line, then wraps parts in `<span>` tags and appends `<br />`.
    /// Since the text itself is escaped, every `<` is markup: strip tags first, then unescape.
    static func plainLines(fromHTML html: String) -> [String] {
        html.replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .unescapingCraftyLogHTML
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .map { String($0.reversed().drop(while: \.isWhitespace).reversed()) }
    }

    /// Lines of the polled buffer that follow what was already shown. The panel keeps a sliding window
    /// (70 lines by default), so the longest suffix of `shown` that starts `current` is the overlap.
    /// Without any overlap the whole buffer is new (e.g. after a restart cleared it).
    static func newLines(after shown: [String], in current: [String]) -> [String] {
        for k in stride(from: min(shown.count, current.count), to: 0, by: -1)
        where shown.suffix(k).elementsEqual(current.prefix(k)) {
            return Array(current.dropFirst(k))
        }
        return current
    }

    static func remember(_ lines: [String], after shown: [String]) -> [String] {
        Array((shown + lines).suffix(memory))
    }
}
