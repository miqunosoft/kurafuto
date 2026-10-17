import XCTest
@testable import Kurafuto

/// Panels are reached over HTTPS only, so passwords and tokens never travel unencrypted.
final class PanelAddressTests: XCTestCase {
    override func tearDown() {
        StubPanel.reset()
        super.tearDown()
    }

    func testOnlyHTTPSAddressesWithAHostAreAccepted() {
        for ok in ["https://192.168.1.20:8443", " https://crafty.home.example ", "HTTPS://[fd00::1]:8443", "https://panel.test/crafty"] {
            XCTAssertNotNil(Instance.panelURL(from: ok), ok)
        }
        for bad in ["http://192.168.1.20:8443", "192.168.1.20:8443", "https://", "ftp://panel.test", "",
                    "https://user:pass@panel.test", "https://panel.test/?next=x", "https://panel.test/#x"] {
            XCTAssertNil(Instance.panelURL(from: bad), bad)
        }
    }

    func testClientSendsNothingToAPlainHTTPAddress() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPanel.self]
        StubPanel.respond(200, #"{"status":"ok","data":[]}"#)
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "http://panel.test:8000")), token: "secret",
                               configuration: configuration)
        do {
            let _: [Server] = try await client.request(.get, "/api/v2/servers")
            XCTFail("expected an error")
        } catch CraftyError.invalidURL {}
        do {
            _ = try await client.rawText("/metrics/host")
            XCTFail("expected an error")
        } catch CraftyError.invalidURL {}
        XCTAssertThrowsError(try client.webSocket("/ws", query: []))
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    func testWebSocketUsesTLS() throws {
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.test:8443")), token: "secret")
        let task = try client.webSocket("/ws", query: [])
        XCTAssertEqual(task.originalRequest?.url?.scheme, "wss")
        task.cancel()
    }

    func testWebPanelLinksNeedHTTPS() throws {
        let app = AppState.preview
        XCTAssertEqual(app.webPanelURL(serverID: "abc", subpage: "backup")?.scheme, "https")
        app.activeInstance?.baseURL = try XCTUnwrap(URL(string: "http://panel.test:8000"))
        XCTAssertNil(app.webPanelURL(serverID: "abc", subpage: "backup"))
    }
}
