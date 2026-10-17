import Foundation
import CryptoKit

/// Thin HTTP client for the Crafty API v2.
/// Response format per spec:  { "status": "ok", "data": ... }  or
///                            { "status": "error", "error": "CODE", "error_data": "..." }
final class APIClient: NSObject, @unchecked Sendable {
    let baseURL: URL
    var token: String?
    private let pinnedSHA256: String?
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    /// Set when an unknown self-signed certificate shows up → the UI asks the user.
    private(set) var lastSeenCertificateSHA256: String?

    /// `configuration` exists for tests; the app always uses an ephemeral session.
    init(baseURL: URL, token: String? = nil, pinnedSHA256: String? = nil,
         configuration: URLSessionConfiguration = .ephemeral) {
        self.baseURL = baseURL
        self.token = token
        self.pinnedSHA256 = pinnedSHA256
        self.configuration = configuration
    }

    struct Envelope<T: Decodable>: Decodable {
        let status: String
        let data: T?
        let error: String?
        let errorData: String?
        enum CodingKeys: String, CodingKey { case status, data, error; case errorData = "error_data" }
    }
    /// Accepts any `data` payload (object, string, number) when the caller doesn't need it.
    struct Empty: Decodable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    enum Body {
        case none
        case json(Encodable)
        case text(String)
        case data(Data)
    }

    func request<T: Decodable>(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: Body = .none,
                               as type: T.Type = T.self) async throws -> T {
        let (data, status) = try await perform(method, path, query: query, body: body)
        let envelope: Envelope<T>
        do { envelope = try JSONDecoder().decode(Envelope<T>.self, from: data) }
        catch {
            guard (200..<300).contains(status) else { throw fail(Self.failure(status: status, error: nil, detail: nil, path: path)) }
            throw CraftyError.decoding(error)
        }
        guard envelope.status == "ok" else {
            throw fail(Self.failure(status: status, error: envelope.error, detail: envelope.errorData, path: path))
        }
        if let d = envelope.data { return d }
        if let e = Empty() as? T { return e }
        throw CraftyError.decoding(URLError(.cannotParseResponse))
    }

    /// For endpoints that answer success without the `{status,data}` envelope (Crafty's backup routes).
    /// Errors still arrive in the envelope.
    func requestUnwrapped<T: Decodable>(_ method: Method, _ path: String, body: Body = .none) async throws -> T {
        let (data, status) = try await perform(method, path, query: [], body: body)
        guard (200..<300).contains(status) else {
            let envelope = try? JSONDecoder().decode(Envelope<Empty>.self, from: data)
            throw fail(Self.failure(status: status, error: envelope?.error, detail: envelope?.errorData, path: path))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CraftyError.decoding(error) }
    }

    /// Crafty's upload route takes raw bytes with the metadata in headers. It answers
    /// `{"status": "ok" | "partial" | "completed"}` and reports errors as
    /// `{"status": "error", "error": …, "data": {"message": …}}`. Returns the status.
    func upload(_ path: String, headers: [String: String], body: Data?) async throws -> String {
        struct Answer: Decodable {
            struct Message: Decodable { let message: String? }
            let status: String
            let error: String?
            let errorData: String?
            let data: Message?
            enum CodingKeys: String, CodingKey { case status, error, errorData = "error_data", data }
            // Only `status` is required; the other fields vary between panel versions and error paths.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                status = try c.decode(String.self, forKey: .status)
                error = try? c.decode(String.self, forKey: .error)
                errorData = try? c.decode(String.self, forKey: .errorData)
                data = try? c.decode(Message.self, forKey: .data)
            }
        }
        let (data, status) = try await perform(.post, path, query: [], body: body.map(Body.data) ?? .none, headers: headers)
        let answer = try? JSONDecoder().decode(Answer.self, from: data)
        guard (200..<300).contains(status), let answer, answer.status != "error" else {
            throw fail(Self.failure(status: status, error: answer?.error, detail: answer?.data?.message ?? answer?.errorData, path: path))
        }
        return answer.status
    }

    private func perform(_ method: Method, _ path: String, query: [URLQueryItem], body: Body,
                         headers: [String: String] = [:]) async throws -> (Data, Int) {
        guard var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw CraftyError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw CraftyError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method.rawValue
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
        switch body {
        case .none: break
        case .json(let value):
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(value))
        case .text(let s):
            req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(s.utf8)
        case .data(let d):
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.httpBody = d
        }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch {
            if let sha = lastSeenCertificateSHA256, pinnedSHA256 == nil {
                throw CraftyError.untrustedCertificate(sha256: sha)
            }
            throw CraftyError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (300..<400).contains(status) { throw CraftyError.redirected }
        return (data, status)
    }

    /// WebSocket on the same pinned, ephemeral session. Crafty reads the token only from the `token`
    /// cookie here, so it travels in a header and never in the URL.
    func webSocket(_ path: String, query: [URLQueryItem]) throws -> URLSessionWebSocketTask {
        guard var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw CraftyError.invalidURL
        }
        comps.scheme = comps.scheme == "http" ? "ws" : "wss"
        comps.percentEncodedQueryItems = query.map {
            URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        }
        guard let url = comps.url else { throw CraftyError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpShouldHandleCookies = false
        if let token { req.setValue("token=\(token)", forHTTPHeaderField: "Cookie") }
        return session.webSocketTask(with: req)
    }

    /// For `/metrics/*` (OpenMetrics text, no JSON envelope).
    func rawText(_ path: String) async throws -> String {
        var req = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 20)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw CraftyError.transport(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (300..<400).contains(status) { throw CraftyError.redirected }
        guard (200..<300).contains(status) else {
            let envelope = try? JSONDecoder().decode(Envelope<Empty>.self, from: data)
            throw fail(Self.failure(status: status, error: envelope?.error, detail: envelope?.errorData, path: path))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Maps a failed response. Crafty answers an invalid or expired token with 403 `ACCESS_DENIED`,
    /// missing rights with 400 `NOT_AUTHORIZED`, and wrong login data with 401 `INCORRECT_CREDENTIALS`.
    static func failure(status: Int, error: String?, detail: String?, path: String) -> CraftyError {
        switch (status, error) {
        case (_, "NOT_AUTHORIZED"): .forbidden(detail ?? path)
        case (401, nil), (401, "ACCESS_DENIED"), (403, "ACCESS_DENIED"): .unauthorized
        case (403, nil): .forbidden(detail ?? path)
        default: .server(code: error ?? "\(status)", detail: detail)
        }
    }

    /// Announces a rejected token so the app can ask for a new sign-in. The notification carries no data.
    private func fail(_ error: CraftyError) -> CraftyError {
        if case .unauthorized = error { NotificationCenter.default.post(name: .panelSessionExpired, object: self) }
        return error
    }
}

extension Notification.Name {
    /// Posted with the `APIClient` as object when the panel rejects its token.
    static let panelSessionExpired = Notification.Name("PanelSessionExpired")
}

// MARK: - Redirects stay on the panel
extension APIClient: URLSessionTaskDelegate {
    /// A redirect is followed only to the panel's own scheme, host and port, so neither a proxy nor a hostile
    /// panel can send the request and its token to another host. Refused redirects end as `CraftyError.redirected`.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let target = request.url, Self.sameOrigin(target, baseURL) else { return nil }
        return request
    }

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? ["https": 443, "wss": 443, "http": 80, "ws": 80][url.scheme?.lowercased() ?? ""] }
        return a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host()?.lowercased() == b.host()?.lowercased()
            && port(a) == port(b)
    }
}

// MARK: - Self-signed certificates (Crafty default) – trust on first use with pinning
extension APIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        // 1. Valid CA certificate (e.g. Let's Encrypt behind a reverse proxy) → continue normally.
        if SecTrustEvaluateWithError(trust, nil) { return (.performDefaultHandling, nil) }

        // 2. Self-signed: only accept if the user has confirmed the fingerprint.
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let der = SecCertificateCopyData(leaf) as Data
        let sha = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
        lastSeenCertificateSHA256 = sha
        if let pinned = pinnedSHA256, pinned == sha {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.cancelAuthenticationChallenge, nil)
    }
}
