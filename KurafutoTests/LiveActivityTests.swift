import XCTest
@testable import Kurafuto

final class LiveActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func stats(running: Bool = false, waiting: Bool = false, ping: Bool = false) -> ServerStats {
        ServerStats(running: running, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20, players: [],
                    waitingStart: waiting, answersPing: ping)
    }

    // MARK: Start-up

    func testStartUpIsReadyOnlyOnceTheServerAnswersPings() {
        var watch = StartUpWatch(started: start)
        XCTAssertEqual(watch.phase(after: stats(), at: start + 1), .running, "the panel has not picked up the start yet")
        XCTAssertEqual(watch.phase(after: stats(waiting: true), at: start + 2), .running)
        XCTAssertEqual(watch.phase(after: stats(running: true), at: start + 4), .running, "the process runs, players cannot join yet")
        XCTAssertEqual(watch.phase(after: nil, at: start + 6), .running, "a failed request is no news")
        XCTAssertEqual(watch.phase(after: stats(running: true, ping: true), at: start + 30), .succeeded)
    }

    func testStartUpFailsWhenTheServerStopsAgainOrNeverRuns() {
        var stopped = StartUpWatch(started: start)
        _ = stopped.phase(after: stats(running: true), at: start + 2)
        XCTAssertEqual(stopped.phase(after: stats(), at: start + 10), .failed)

        var never = StartUpWatch(started: start)
        XCTAssertEqual(never.phase(after: stats(), at: start + StartUpWatch.launchLimit - 1), .running)
        XCTAssertEqual(never.phase(after: stats(), at: start + StartUpWatch.launchLimit + 1), .failed)
    }

    func testStartUpIsDroppedWhenTheServerNeverAnswers() {
        var watch = StartUpWatch(started: start)
        XCTAssertEqual(watch.phase(after: stats(running: true), at: start + 60), .running)
        XCTAssertNil(watch.phase(after: stats(running: true), at: start + StartUpWatch.readyLimit + 1))
    }

    func testPingResultIsReadFromThePanelsText() throws {
        func decode(_ value: String) throws -> Bool {
            let json = #"{"running": true, "cpu": 1, "mem": "1GB", "mem_percent": 5, "online": 0, "max": 20, "players": "[]""#
                + (value.isEmpty ? "" : #", "int_ping_results": "# + value) + "}"
            return try JSONDecoder().decode(ServerStats.self, from: Data(json.utf8)).answersPing
        }
        XCTAssertTrue(try decode(#""True""#))
        XCTAssertFalse(try decode(#""False""#))
        XCTAssertFalse(try decode(#""""#))
        XCTAssertTrue(try decode("true"))
        XCTAssertFalse(try decode(""))
    }

    // MARK: Backups

    func testBackupStatusEventsAreParsed() throws {
        let first = try XCTUnwrap(CraftyConsoleFeed.backupStatus(fromSocketMessage:
            #"{"event": "backup_status", "data": {"percent": 0, "total_files": "1.2GB"}}"#))
        XCTAssertEqual(first.percent, 0)
        XCTAssertNil(first.backupID, "the panel's first event names no config")

        let step = try XCTUnwrap(CraftyConsoleFeed.backupStatus(fromSocketMessage:
            #"{"event": "backup_status", "data": {"percent": 42.17, "total_files": "1.2GB", "backup_id": "b4665-a3"}}"#))
        XCTAssertEqual(step.percent, 42.17)
        XCTAssertEqual(step.backupID, "b4665-a3")

        let over = CraftyConsoleFeed.backupStatus(fromSocketMessage: #"{"event":"backup_status","data":{"percent":140}}"#)
        XCTAssertEqual(over?.percent, 100)
        XCTAssertNil(CraftyConsoleFeed.backupStatus(fromSocketMessage: #"{"event":"vterm_new_line","data":{"line":"x"}}"#))
        XCTAssertNil(CraftyConsoleFeed.backupStatus(fromSocketMessage: #"{"event":"backup_status","data":{"percent":"half"}}"#))
        XCTAssertNil(CraftyConsoleFeed.backupStatus(fromSocketMessage: "not json"))
    }

    func testBackupResultComesFromTheConfigStatus() {
        XCTAssertEqual(BackupConfig.lastRunFailed(status: #"{"status": "Failed", "message": "Recursive backup target"}"#), true)
        XCTAssertEqual(BackupConfig.lastRunFailed(status: #"{"status": "Standby", "message": ""}"#), false)
        XCTAssertNil(BackupConfig.lastRunFailed(status: "Standby"))
    }

    func testMockReportsProgressThenTheResult() async {
        var events: [BackupProgress] = []
        for await event in MockCraftyService(latency: .zero).backupProgress(serverID: MockData.survivalID, idleTimeout: nil) {
            events.append(event)
        }
        XCTAssertEqual(events.last, .finished(failed: false))
        let done = events.compactMap { if case .running(let done) = $0 { done } else { nil } }
        XCTAssertEqual(done.count, 10)
        XCTAssertEqual(done, done.sorted())
        XCTAssertTrue(done.allSatisfy { (0...1).contains($0) })
    }

    // MARK: Activity content

    func testAttributesNameTheServerOnlyWhenAllowedAndLinkIntoTheApp() throws {
        let startUp = ServerActivityAttributes(kind: .startUp, serverID: "abc-123", serverName: "Survival", started: start,
                                               mode: .dark, accent: .cyan)
        XCTAssertEqual(startUp.displayName, "Survival")
        XCTAssertEqual(startUp.link, ServerLink.url(serverID: "abc-123", screen: .console))
        XCTAssertEqual(startUp.status(.init(phase: .running)), "Starting…")
        XCTAssertEqual(startUp.status(.init(phase: .succeeded)), "Ready for players")

        let backup = ServerActivityAttributes(kind: .backup, serverID: "abc-123", serverName: nil, started: start,
                                              mode: .light, accent: .pink)
        XCTAssertEqual(backup.displayName, "Server", "with the app lock on, the Lock Screen shows no server name")
        XCTAssertEqual(backup.link, ServerLink.url(serverID: "abc-123", screen: .details))
        XCTAssertEqual(backup.status(.init(phase: .failed)), "Backup failed")

        let decoded = try JSONDecoder().decode(ServerActivityAttributes.self, from: JSONEncoder().encode(backup))
        XCTAssertNil(decoded.serverName)
        XCTAssertEqual(decoded.accent, .pink)
    }
}
