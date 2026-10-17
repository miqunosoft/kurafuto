import XCTest
@testable import Kurafuto

/// The client follows redirects only within the panel's origin, so the token never reaches another host.
final class RedirectTests: XCTestCase {
    override func tearDown() {
        RedirectingPanel.reset()
        super.tearDown()
    }

    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingPanel.self]
        return APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.test:8443")), token: "secret", configuration: configuration)
    }

    func testRedirectToAnotherHostIsRefused() async throws {
        RedirectingPanel.target = "https://elsewhere.test/api/v2/servers"
        do {
            let _: [Server] = try await client().request(.get, "/api/v2/servers")
            XCTFail("expected an error")
        } catch CraftyError.redirected {}
        XCTAssertEqual(RedirectingPanel.hosts, ["panel.test"])
    }

    func testRedirectToAnotherPortOrSchemeIsRefused() async throws {
        for target in ["https://panel.test:9443/api/v2/servers", "http://panel.test:8443/api/v2/servers"] {
            RedirectingPanel.reset()
            RedirectingPanel.target = target
            do {
                let _: [Server] = try await client().request(.get, "/api/v2/servers")
                XCTFail("expected an error for \(target)")
            } catch CraftyError.redirected {}
            XCTAssertEqual(RedirectingPanel.hosts, ["panel.test"], target)
        }
    }

    func testRedirectWithinThePanelIsFollowed() async throws {
        RedirectingPanel.target = "https://PANEL.test:8443/api/v2/servers/"
        let servers: [Server] = try await client().request(.get, "/api/v2/servers")
        XCTAssertTrue(servers.isEmpty)
        XCTAssertEqual(RedirectingPanel.hosts, ["panel.test", "panel.test"])
    }

    func testSameOriginComparesSchemeHostAndDefaultPort() throws {
        let base = try XCTUnwrap(URL(string: "https://panel.test"))
        XCTAssertTrue(APIClient.sameOrigin(try XCTUnwrap(URL(string: "https://panel.test:443/x")), base))
        XCTAssertFalse(APIClient.sameOrigin(try XCTUnwrap(URL(string: "https://panel.test.evil.test/x")), base))
        XCTAssertFalse(APIClient.sameOrigin(try XCTUnwrap(URL(string: "http://panel.test/x")), base))
    }
}

/// Answers the first request with a redirect to `target` and every later one with an empty server list.
final class RedirectingPanel: URLProtocol {
    nonisolated(unsafe) static var target = ""
    nonisolated(unsafe) static var hosts: [String] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { target = ""; hosts = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let first = Self.lock.withLock {
            Self.hosts.append(url.host()?.lowercased() ?? "")
            return Self.hosts.count == 1
        }
        if first, let next = URL(string: Self.target),
           let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": Self.target]) {
            var redirect = request
            redirect.url = next
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data(#"{"status":"ok","data":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
