import XCTest
@testable import ThrawnApp

private final class StubCredentialStore: DeployedAgentCredentialStore {
    var passwordValue: String? = "password-once"
    var refreshValue: String?
    var passwordReads = 0
    var refreshReads = 0
    var savedRefreshTokens: [String] = []
    var clearCount = 0

    init(refresh: String?) { self.refreshValue = refresh }

    func password(for config: DeployedAgentConfig) -> String? {
        passwordReads += 1
        return passwordValue
    }

    func refreshToken(for config: DeployedAgentConfig) -> String? {
        refreshReads += 1
        return refreshValue
    }

    func saveRefreshToken(_ token: String, for config: DeployedAgentConfig) throws {
        savedRefreshTokens.append(token)
        refreshValue = token
    }

    func clearRefreshToken(for config: DeployedAgentConfig) {
        clearCount += 1
        refreshValue = nil
    }
}

private final class DeployedAgentURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (code, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class DeployedAgentClientAuthTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeployedAgentURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var config: DeployedAgentConfig {
        DeployedAgentConfig(
            id: "test", name: "Test", appName: "Test App", mention: "test",
            baseURL: URL(string: "https://app.example.test")!,
            supabaseURL: URL(string: "https://db.example.test")!,
            supabaseAnonKey: "public-anon-key",
            email: "agent@example.test", keychainService: "test-agent"
        )
    }

    private static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    override func tearDown() {
        DeployedAgentURLProtocol.handler = nil
        super.tearDown()
    }

    func testPersistedRefreshTokenRenewsExistingSessionWithoutReadingPassword() async throws {
        let credentials = StubCredentialStore(refresh: "refresh-1")
        var authRequests = 0
        var statusRequests = 0
        DeployedAgentURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/token" {
                authRequests += 1
                XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
                return (200, try Self.json([
                    "access_token": "access-1", "refresh_token": "refresh-2", "expires_in": 3600,
                ]))
            }
            statusRequests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
            return (200, try Self.json([
                "ok": true, "provider": "OpenAI", "model": "gpt-test",
                "capabilities": [], "providers_available": [:],
            ]))
        }

        let client = DeployedAgentClient(config: config, session: session(), credentials: credentials)
        _ = try await client.status()
        _ = try await client.status()

        XCTAssertEqual(authRequests, 1)
        XCTAssertEqual(statusRequests, 2)
        XCTAssertEqual(credentials.passwordReads, 0)
        XCTAssertEqual(credentials.savedRefreshTokens, ["refresh-2"])
    }

    func testRejectedRefreshFallsBackToPasswordExactlyOnceAndRotatesCredential() async throws {
        let credentials = StubCredentialStore(refresh: "revoked-refresh")
        var grants: [String] = []
        DeployedAgentURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/token" {
                let grant = request.url?.query ?? ""
                grants.append(grant)
                if grant == "grant_type=refresh_token" {
                    return (400, try Self.json(["error": "invalid_grant"]))
                }
                return (200, try Self.json([
                    "access_token": "access-new", "refresh_token": "refresh-new", "expires_in": 3600,
                ]))
            }
            return (200, try Self.json([
                "ok": true, "provider": "OpenAI", "model": "gpt-test",
                "capabilities": [], "providers_available": [:],
            ]))
        }

        let client = DeployedAgentClient(config: config, session: session(), credentials: credentials)
        _ = try await client.status()

        XCTAssertEqual(grants, ["grant_type=refresh_token", "grant_type=password"])
        XCTAssertEqual(credentials.clearCount, 1)
        XCTAssertEqual(credentials.passwordReads, 1)
        XCTAssertEqual(credentials.savedRefreshTokens, ["refresh-new"])
    }

    func testConcurrentPresenceChecksCoalesceOneRefreshGrant() async throws {
        let credentials = StubCredentialStore(refresh: "refresh-1")
        let countLock = NSLock()
        var authRequests = 0
        DeployedAgentURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/token" {
                countLock.lock(); authRequests += 1; countLock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                return (200, try Self.json([
                    "access_token": "access-1", "refresh_token": "refresh-2", "expires_in": 3600,
                ]))
            }
            return (200, try Self.json([
                "ok": true, "provider": "OpenAI", "model": "gpt-test",
                "capabilities": [], "providers_available": [:],
            ]))
        }

        let client = DeployedAgentClient(config: config, session: session(), credentials: credentials)
        async let first = client.status()
        async let second = client.status()
        _ = try await (first, second)

        let finalCount = countLock.withLock { authRequests }
        XCTAssertEqual(finalCount, 1)
        XCTAssertEqual(credentials.passwordReads, 0)
    }
}
