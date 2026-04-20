import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Gemini OAuth2 Client
//
// Full OAuth2 desktop app flow for Google Gemini.
// User signs in with their Google account — same one used for Gemini.
// Free tier included. Google AI Pro/Ultra subscribers get full access.
//
// Flow:
//   1. Open system browser → Google consent screen
//   2. Local HTTP server catches redirect on localhost
//   3. Exchange auth code for access + refresh tokens
//   4. Store refresh token in Keychain
//   5. Auto-refresh access token on expiry

@MainActor
final class GeminiOAuthClient: ObservableObject {
    @Published var authenticated = false
    @Published var authenticating = false
    @Published var userEmail: String?
    @Published var lastError: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?

    // OAuth2 configuration — Desktop app client
    // Register your own desktop OAuth client in Google Cloud Console and
    // supply the values via environment variables (THRAWN_GEMINI_CLIENT_ID /
    // THRAWN_GEMINI_CLIENT_SECRET) or Keychain (service: com.thrawn.gemini.oauth,
    // accounts: client-id / client-secret). Nothing is hardcoded so the source
    // tree stays safe to commit and publish.
    private let clientId: String = {
        if let env = ProcessInfo.processInfo.environment["THRAWN_GEMINI_CLIENT_ID"], !env.isEmpty { return env }
        return KeychainHelper.read(service: "com.thrawn.gemini.oauth", account: "client-id") ?? ""
    }()
    private let clientSecret: String = {
        if let env = ProcessInfo.processInfo.environment["THRAWN_GEMINI_CLIENT_SECRET"], !env.isEmpty { return env }
        return KeychainHelper.read(service: "com.thrawn.gemini.oauth", account: "client-secret") ?? ""
    }()
    // OAuth2 scopes:
    // - openid + email + profile → native sign-in identity
    // - cloud-platform → access Gemini API (universal, no per-project API enabling needed)
    private let scopes = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cloud-platform"
    ].joined(separator: " ")

    /// Version tag — bump this when scopes change to force re-auth
    private let scopeVersion = "v4-thrawn-project"

    private let keychainService = "com.thrawn.gemini.oauth"
    private let keychainRefreshAccount = "refresh-token"
    private let keychainEmailAccount = "user-email"
    private let keychainScopeVersion = "scope-version"

    private var callbackServer: GeminiOAuthCallbackServer?

    init() {
        // Check if stored tokens match the current scope version.
        // If scope version is nil (pre-versioning tokens) or mismatched,
        // the old tokens won't have the right scopes — wipe them.
        let storedVersion = KeychainHelper.read(service: keychainService, account: keychainScopeVersion)
        let hasStoredTokens = KeychainHelper.read(service: keychainService, account: keychainRefreshAccount) != nil

        if storedVersion == scopeVersion,
           let storedRefresh = KeychainHelper.read(service: keychainService, account: keychainRefreshAccount) {
            // Tokens match current scopes — restore them
            refreshToken = storedRefresh
            userEmail = KeychainHelper.read(service: keychainService, account: keychainEmailAccount)
            authenticated = true
            Task { await silentRefresh() }
        } else if hasStoredTokens {
            // Old tokens with wrong/missing scopes — wipe them
            print("[GeminiOAuth] Clearing outdated tokens (scope: \(storedVersion ?? "nil") → \(scopeVersion))")
            KeychainHelper.delete(service: keychainService, account: keychainRefreshAccount)
            KeychainHelper.delete(service: keychainService, account: keychainEmailAccount)
            KeychainHelper.delete(service: keychainService, account: keychainScopeVersion)
        }
    }

    /// Explicitly re-check Keychain for stored tokens (e.g. after setup wizard saves them).
    func loadStoredTokens() {
        guard !authenticated else { return }
        // Only load if scope version matches
        let storedVersion = KeychainHelper.read(service: keychainService, account: keychainScopeVersion)
        guard storedVersion == scopeVersion else { return }
        if let storedRefresh = KeychainHelper.read(service: keychainService, account: keychainRefreshAccount) {
            refreshToken = storedRefresh
            userEmail = KeychainHelper.read(service: keychainService, account: keychainEmailAccount)
            authenticated = true
            Task { await silentRefresh() }
        }
    }

    // MARK: - OAuth2 Flow

    /// Start the full OAuth2 flow: opens browser, waits for callback.
    func startOAuthFlow() async {
        authenticating = true
        lastError = nil

        do {
            // 1. Start local callback server
            let server = GeminiOAuthCallbackServer()
            self.callbackServer = server
            let port = try await server.start()

            let redirectURI = "http://127.0.0.1:\(port)/callback"

            // 2. Build authorization URL
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]

            guard let authURL = components.url else {
                throw OAuthError.invalidURL
            }

            // 3. Open system browser
            #if os(macOS)
            NSWorkspace.shared.open(authURL)
            #endif

            // 4. Wait for callback with authorization code
            let code = try await server.waitForCode(timeoutSeconds: 120)

            // 5. Exchange code for tokens
            try await exchangeCodeForTokens(code: code, redirectURI: redirectURI)

            // 6. Get user info
            await fetchUserEmail()

            authenticating = false
            authenticated = true

            // Save scope version so we know these tokens have the right scopes
            KeychainHelper.save(service: keychainService, account: keychainScopeVersion, value: scopeVersion)

            // Save provider state
            ProviderStateStore.setConnected(ProviderCredential(
                provider: .gemini,
                model: AIProvider.gemini.defaultModel,
                isConnected: true,
                lastValidated: Date(),
                keychainService: keychainService,
                hasRefreshToken: true,
                userEmail: userEmail
            ))

        } catch {
            authenticating = false
            lastError = error.localizedDescription
        }

        callbackServer?.stop()
        callbackServer = nil
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "redirect_uri=\(redirectURI)",
            "grant_type=authorization_code"
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenExchangeFailed
        }

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed
        }

        self.accessToken = accessToken
        let expiresIn = json["expires_in"] as? Int ?? 3600
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60))

        if let refresh = json["refresh_token"] as? String {
            self.refreshToken = refresh
            KeychainHelper.save(service: keychainService, account: keychainRefreshAccount, value: refresh)
        }
    }

    // MARK: - Token Refresh

    func refreshAccessToken() async throws {
        guard let refreshToken else {
            throw OAuthError.noRefreshToken
        }

        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token=\(refreshToken)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenRefreshFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw OAuthError.tokenRefreshFailed
        }

        self.accessToken = newAccessToken
        let expiresIn = json["expires_in"] as? Int ?? 3600
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
    }

    private func silentRefresh() async {
        do {
            try await refreshAccessToken()
            authenticated = true
        } catch {
            // Refresh failed — user needs to re-auth
            authenticated = false
            lastError = "Session expired. Please sign in again."
        }
    }

    /// Get a valid access token, refreshing if needed.
    func getAccessToken() async -> String? {
        if let tokenExpiresAt, Date() >= tokenExpiresAt {
            try? await refreshAccessToken()
        }
        return accessToken
    }

    // MARK: - User Info

    private func fetchUserEmail() async {
        guard let token = accessToken,
              let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                userEmail = email
                KeychainHelper.save(service: keychainService, account: keychainEmailAccount, value: email)
            }
        } catch {
            // Non-critical
        }
    }

    // MARK: - Sign Out

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userEmail = nil
        authenticated = false
        KeychainHelper.delete(service: keychainService, account: keychainRefreshAccount)
        KeychainHelper.delete(service: keychainService, account: keychainEmailAccount)
        KeychainHelper.delete(service: keychainService, account: keychainScopeVersion)
        ProviderStateStore.disconnect(.gemini)
    }

    // MARK: - Errors

    enum OAuthError: LocalizedError {
        case invalidURL
        case tokenExchangeFailed
        case tokenRefreshFailed
        case noRefreshToken
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid OAuth URL."
            case .tokenExchangeFailed: return "Failed to exchange authorization code."
            case .tokenRefreshFailed: return "Failed to refresh access token."
            case .noRefreshToken: return "No refresh token available. Please sign in again."
            case .timeout: return "Sign-in timed out. Please try again."
            }
        }
    }
}

// MARK: - OAuth Callback Server
//
// Ephemeral local HTTP server that listens for the OAuth redirect.
// Runs on a random port, captures the auth code, and shuts down.

final class GeminiOAuthCallbackServer: @unchecked Sendable {
    private var listener: Any?  // NWListener (Network.framework)
    private var port: UInt16 = 0
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var httpFileHandle: FileHandle?
    private var serverSocket: Int32 = -1

    /// Start the callback server, return the port.
    func start() async throws -> UInt16 {
        // Use a simple BSD socket to avoid Network.framework complexity
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw GeminiOAuthClient.OAuthError.invalidURL }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // Random port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var addrCopy = addr
        let bindResult = withUnsafePointer(to: &addrCopy) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw GeminiOAuthClient.OAuthError.invalidURL }

        // Get assigned port
        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        getsockname(serverSocket, withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }, &addrLen)
        port = UInt16(bigEndian: boundAddr.sin_port)

        listen(serverSocket, 1)
        return port
    }

    /// Wait for the auth code from the redirect, with timeout.
    func waitForCode(timeoutSeconds: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self, self.serverSocket >= 0 else {
                    continuation.resume(throwing: GeminiOAuthClient.OAuthError.timeout)
                    return
                }

                // Set socket timeout
                var timeout = timeval(tv_sec: __darwin_time_t(timeoutSeconds), tv_usec: 0)
                setsockopt(self.serverSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                let clientSocket = accept(self.serverSocket, nil, nil)
                guard clientSocket >= 0 else {
                    continuation.resume(throwing: GeminiOAuthClient.OAuthError.timeout)
                    return
                }

                // Read the HTTP request
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                let requestString = bytesRead > 0 ? String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? "" : ""

                // Extract the code from the query string
                if let codeRange = requestString.range(of: "code="),
                   let endRange = requestString[codeRange.upperBound...].rangeOfCharacter(from: CharacterSet(charactersIn: "& ")) {
                    let code = String(requestString[codeRange.upperBound..<endRange.lowerBound])

                    // Send success response
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html\r
                    Connection: close\r
                    \r
                    <html><body style="background:#0a0e14;color:#7ba7bc;font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;">
                    <div style="text-align:center"><h1 style="font-size:2em;letter-spacing:4px;">✓ THRAWN</h1><p>Signed in successfully. You can close this tab.</p></div>
                    </body></html>
                    """
                    _ = response.withCString { write(clientSocket, $0, strlen($0)) }
                    close(clientSocket)

                    continuation.resume(returning: code)
                } else {
                    // Send error response
                    let response = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nNo authorization code received."
                    _ = response.withCString { write(clientSocket, $0, strlen($0)) }
                    close(clientSocket)

                    continuation.resume(throwing: GeminiOAuthClient.OAuthError.tokenExchangeFailed)
                }
            }
        }
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
}
