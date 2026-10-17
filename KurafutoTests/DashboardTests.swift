import XCTest
@testable import Kurafuto

/// The Servers tab's data: stats history from the panel, memory values and the dashboard model.
@MainActor
final class DashboardTests: XCTestCase {
    func testPanelSizesAreReadAsBytes() {
        XCTAssertEqual(ByteSize.bytes(fromPanelText: "1.4GB") ?? 0, 1.4 * 1_073_741_824, accuracy: 1)
        XCTAssertEqual(ByteSize.bytes(fromPanelText: " 640MB"), 640 * 1_048_576)
        XCTAssertEqual(ByteSize.bytes(fromPanelText: "0MB"), 0)
        XCTAssertEqual(ByteSize.bytes(fromPanelText: "1480200192.0"), 1_480_200_192)
        XCTAssertNil(ByteSize.bytes(fromPanelText: "False"))
    }

    func testMemoryCeilingComesFromXmx() {
        var server = MockData.servers[0]
        XCTAssertEqual(server.maxMemoryBytes, 4 * 1_073_741_824)
        server.executionCommand = "java -Xms1000M -Xmx2000M -jar paper.jar nogui"
        XCTAssertEqual(server.maxMemoryBytes, 2000 * 1_048_576)
        server.executionCommand = "./bedrock_server"
        XCTAssertNil(server.maxMemoryBytes)
    }

    func testHistoryRowsBecomeSamples() throws {
        // 4.11.0 rows of GET /api/v2/servers/{id}/history (server row shortened): bytes as a number, running and stopped.
        let json = """
        {"status":"ok","data":[
        {"stats_id":45,"created":"2026-10-15T11:38:14.7","server_id":{"server_id":"x"},"started":"2026-10-15 09:30:00","running":true,"cpu":23.5,"mem":1480200192.0,"mem_percent":17.0,"online":2,"max":20,"players":"['a', 'b']","crashed":false},
        {"stats_id":44,"created":"2026-10-15T11:37:44.721351","server_id":{"server_id":"x"},"started":"False","running":false,"cpu":0.0,"mem":0.0,"mem_percent":0.0,"online":0,"max":0,"players":"False","crashed":false},
        {"stats_id":43,"created":"not a date","running":true,"cpu":1.0,"mem":"1.0GB"}]}
        """
        let envelope = try JSONDecoder().decode(APIClient.Envelope<[StatsHistoryRow]>.self, from: Data(json.utf8))
        let samples = try XCTUnwrap(envelope.data).compactMap(\.sample).sorted { $0.date < $1.date }
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].cpu, 0)
        XCTAssertEqual(samples[1].cpu, 23.5)
        XCTAssertEqual(samples[1].memBytes, 1_480_200_192)
        XCTAssertEqual(samples[1].date.timeIntervalSince(samples[0].date), 30, accuracy: 0.001)
    }

    func testHistoryIsRequestedFromThePanel() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPanel.self]
        defer { StubPanel.reset() }
        let live = LiveCraftyService(client: APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.test")),
                                                       token: "t", configuration: configuration))
        StubPanel.respond(200, #"{"status":"ok","data":[]}"#)
        let samples = try await live.statsHistory(serverID: "abc")
        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(StubPanel.requests.map(\.line), ["GET /api/v2/servers/abc/history"])
    }

    func testPixelFacesAreStablePerName() {
        XCTAssertEqual(PixelFace(name: "miquno"), PixelFace(name: "miquno"))
        XCTAssertEqual(PixelFace(name: "Miquno"), PixelFace(name: "miquno"), "Minecraft names are case-insensitive")
        let faces = Set(["Steve_DE", "miquno", "Alex2010", "MasterBuilder", "PocketHero"].map { "\(PixelFace(name: $0))" })
        XCTAssertGreaterThan(faces.count, 3, "different players should mostly look different")
    }

    func testModelSelectsTheBusiestServerAndListsCrashes() async {
        let model = DashboardModel()
        model.attach(MockCraftyService(latency: .zero))
        await model.load()
        XCTAssertEqual(model.selected?.id, MockData.survivalID, "the running server with the most players")
        XCTAssertEqual(model.crashed.map(\.id), [MockData.modpackID])
        XCTAssertEqual(model.onlineCount, 2)
        XCTAssertEqual(model.playerCount, 5)
        XCTAssertEqual(model.history[MockData.survivalID]?.count, 120, "an hour of samples every 30 s")
        XCTAssertFalse(model.consoleTail[MockData.survivalID]?.isEmpty ?? true)
    }

    func testStoppingUpdatesTheSelectedServer() async {
        let model = DashboardModel()
        model.attach(MockCraftyService(latency: .zero))
        await model.load()
        let server = MockData.servers[0]
        let accepted = await model.perform(.stop, on: server)
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.stats[server.id]?.running, false)
        XCTAssertNil(model.busy)
        XCTAssertNil(model.actionError)
    }
}
