import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import C67Domain

/// One actor owns native Apple/email session transitions, refresh rotation and PKCE email commands.
public actor SupabaseAuthentication: TravellerAuthentication {
    public static let callbackURL = URL(string: "c67://auth/callback")!
    private let connection: SupabaseConnection
    private let store: any SessionStore
    private let flowStore: (any SessionStore)?
    private let now: @Sendable () -> Date
    private var record: SessionRecord?
    private var pending: EmailFlow?
    private var restored = false
    private var generation = UUID()
    private var busy = false
    private var refresh: (id: UUID, task: Task<SessionRecord, Error>)?
    private var observers: [UUID: AsyncStream<AuthenticationSnapshot>.Continuation] = [:]

    public init(baseURL: URL, clientKey: String, store: any SessionStore, flowStore: (any SessionStore)? = nil,
                session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) throws {
        connection = try .init(baseURL: baseURL, clientKey: clientKey, session: session)
        self.store = store; self.flowStore = flowStore; self.now = now
    }

    public func sessionChanges() -> AsyncStream<AuthenticationSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AuthenticationSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(16))
        observers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private var snapshot: AuthenticationSnapshot {
        .init(account: record?.account, sessionID: generation, requiresPasswordReset: record?.isRecovery == true,
              isRestored: restored, pendingEmail: pending?.email, pendingRecovery: pending?.kind == .recovery)
    }
    private func publish() { for observer in observers.values { observer.yield(snapshot) } }

    public func currentAccount() async throws -> TravellerAccount? { try await validSession()?.account }
    public func refreshSession() async throws -> TravellerAccount? { try await validSession(forceRefresh: true)?.account }
    public func accessToken() async throws -> String? {
        let session = try await validSession()
        guard session?.isRecovery != true else { throw AuthenticationError.passwordResetRequired }
        return session?.accessToken
    }

    /// A ticket binds a private response to the same login that authorized its request.
    struct Authorization: Sendable { let token: String; let sessionID: UUID }
    func authorization() async throws -> Authorization? {
        let operation = generation
        guard let token = try await accessToken() else { return nil }
        guard generation == operation else { throw CancellationError() }
        return .init(token: token, sessionID: operation)
    }
    func isCurrent(_ value: Authorization) -> Bool {
        generation == value.sessionID && record != nil && record?.isRecovery != true
    }

    public func signIn(email: String, password: String) async throws -> TravellerAccount {
        try beginAction()
        defer { busy = false }
        let email = try validateEmail(email)
        guard !password.isEmpty else { throw AuthenticationError.invalidCredentials }
        // Load an earlier email verifier before changing in-memory state. A fresh login can repair a corrupt record.
        try? restore()
        // An early login attempt for the same pending signup must not lose its confirmation verifier.
        let operation = try clearSession(clearFlow: pending?.email != email)
        let result = try await token(grant: "password", body: Credentials(email: email, password: password))
        try check(operation)
        try install(result)
        try saveFlow(nil)
        return result.account
    }

    public func signInWithApple(_ credentials: AppleSignInCredentials) async throws -> TravellerAccount {
        try beginAction(); defer { busy = false }
        guard !credentials.identityToken.isEmpty, credentials.identityToken.utf8.count <= 32768,
              credentials.nonce.count >= 32, credentials.nonce.count <= 256,
              !credentials.userID.isEmpty, credentials.userID.count <= 512 else {
            throw AuthenticationError.invalidAppleCredential
        }
        let operation = try clearSession(clearFlow: true)
        var result = try await token(grant: "id_token", body: AppleToken(id_token: credentials.identityToken, nonce: credentials.nonce))
        try check(operation)
        // Apple verifies the native credential; GoTrue verifies its signature, audience and nonce.
        // This identifier is only for local credential-revocation checks, never server authorization.
        result.appleUserID = credentials.userID
        try install(result)
        return result.account
    }

    public func currentAppleUserID() throws -> String? { try restore(); return record?.appleUserID }

    public func invalidateAppleSession(userID: String) async throws {
        try restore()
        guard record?.appleUserID == userID else { return }
        try await signOut()
    }

    public func signUp(email: String, password: String) async throws {
        try beginAction(); defer { busy = false }
        let email = try validateEmail(email)
        try validatePassword(password)
        let operation = try clearSession(clearFlow: true)
        let flow = try makeFlow(email: email, kind: .signup)
        try saveFlow(flow)
        do {
            let data = try await send("signup", body: Signup(email: email, password: password,
                                                             code_challenge: flow.challenge), redirect: flow.redirect)
            try check(operation)
            // Autoconfirm is allowed in isolated tests; shared homelab keeps confirmation required.
            if let value = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                try install(try value.session(now: now(), recovery: false))
                try saveFlow(nil)
            } else {
                _ = try JSONDecoder().decode(SignupUser.self, from: data)
                publish()
            }
        } catch {
            // Retain the verifier after uncertain responses: the email may already have been sent.
            throw error
        }
    }

    public func resendConfirmation() async throws {
        try beginAction(); defer { busy = false }
        try restore()
        guard let flow = pending, flow.kind == .signup else { throw AuthenticationError.emailFlowUnavailable }
        try validateFlow(flow)
        let operation = generation
        _ = try await send("resend", body: Resend(email: flow.email, code_challenge: flow.challenge), redirect: flow.redirect)
        try check(operation)
    }

    public func sendPasswordReset(email: String) async throws {
        try beginAction(); defer { busy = false }
        let email = try validateEmail(email)
        let operation = try clearSession(clearFlow: true)
        let flow = try makeFlow(email: email, kind: .recovery)
        try saveFlow(flow)
        _ = try await send("recover", body: Recover(email: email, code_challenge: flow.challenge), redirect: flow.redirect)
        try check(operation)
        publish()
    }

    public func handleCallback(_ url: URL) async throws {
        try beginAction(); defer { busy = false }
        try restore()
        guard let flow = pending else { throw AuthenticationError.emailFlowUnavailable }
        try validateFlow(flow)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.callbackURL.scheme, components.host == Self.callbackURL.host,
              components.path == Self.callbackURL.path, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else { throw AuthenticationError.invalidCallback }
        let items = components.queryItems ?? []
        // Reject ambiguous duplicates, token-bearing implicit callbacks and unrelated query parameters.
        guard Set(items.map(\.name)).count == items.count,
              Set(items.map(\.name)).isSubset(of: ["state", "code", "error", "error_code", "error_description"]),
              items.first(where: { $0.name == "state" })?.value == flow.id.uuidString else {
            throw AuthenticationError.invalidCallback
        }
        if items.contains(where: { $0.name == "error" || $0.name == "error_code" }) {
            throw AuthenticationError.emailFlowExpired
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 2048 else { throw AuthenticationError.invalidCallback }
        let operation = generation
        let result = try await token(grant: "pkce", body: CodeExchange(auth_code: code, code_verifier: flow.verifier),
                                     recovery: flow.kind == .recovery)
        try check(operation)
        guard result.account.email?.lowercased() == flow.email else { throw AuthenticationError.invalidCallback }
        try install(result)
        try saveFlow(nil)
    }

    public func updatePassword(_ password: String) async throws {
        try beginAction(); defer { busy = false }
        try validatePassword(password)
        guard let current = try await validSession(allowBusy: true) else { throw AuthenticationError.sessionExpired }
        let operation = generation
        do {
            _ = try await send("user", method: "PUT", body: Password(password: password), token: current.accessToken)
        } catch AuthenticationError.sessionExpired {
            _ = try clearSession(clearFlow: true)
            throw AuthenticationError.sessionExpired
        }
        try check(operation)
        // The recovery credential becomes a regular session only after the server accepts the new password.
        try install(.init(account: current.account, accessToken: current.accessToken,
                          refreshToken: current.refreshToken, expiresAt: current.expiresAt, recovery: false))
    }

    public func cancelEmailFlow() throws { _ = try clearSession(clearFlow: true) }

    public func invalidateSession(rejectedToken: String) throws {
        try restore()
        guard record?.accessToken == rejectedToken else { return }
        _ = try clearSession(clearFlow: false)
    }

    public func signOut() async throws {
        try? restore()
        let token = record?.accessToken
        _ = try clearSession(clearFlow: true)
        guard let token else { return }
        do {
            _ = try await send("logout", body: Empty(), token: token,
                               query: [.init(name: "scope", value: "local")])
        } catch { throw AuthenticationError.remoteSignOutFailed }
    }

    private func validSession(forceRefresh: Bool = false, allowBusy: Bool = false) async throws -> SessionRecord? {
        if busy && !allowBusy { throw AuthenticationError.operationInProgress }
        try restore()
        guard let current = record else { return nil }
        if !forceRefresh && current.expiresAt.timeIntervalSince(now()) > 60 { return current }
        let operation = generation
        let flight: (id: UUID, task: Task<SessionRecord, Error>)
        if let refresh { flight = refresh }
        else {
            let id = UUID()
            flight = (id, Task { try await self.rotate(current, operation: operation, flightID: id) })
            refresh = flight
        }
        let value = try await flight.task.value
        try check(operation)
        return value
    }
    private func rotate(_ current: SessionRecord, operation: UUID, flightID: UUID) async throws -> SessionRecord {
        defer { if refresh?.id == flightID { refresh = nil } }
        do {
            var value = try await token(grant: "refresh_token", body: RefreshToken(refresh_token: current.refreshToken),
                                        recovery: current.isRecovery)
            guard generation == operation else { throw CancellationError() }
            guard value.account.id == current.account.id else { throw AuthenticationError.invalidResponse }
            value.appleUserID = current.appleUserID
            try persist(value)
            record = value
            publish()
            return value
        } catch {
            guard generation == operation else { throw CancellationError() }
            if error as? AuthenticationError == .sessionExpired { _ = try clearSession(clearFlow: false) }
            throw error
        }
    }
    private func check(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard generation == operation else { throw CancellationError() }
    }
    private func beginAction() throws {
        guard !busy else { throw AuthenticationError.operationInProgress }
        busy = true
    }
    @discardableResult private func clearSession(clearFlow: Bool) throws -> UUID {
        generation = UUID()
        refresh?.task.cancel(); refresh = nil
        record = nil; restored = true
        publish()
        try persist(nil)
        if clearFlow { try saveFlow(nil) }
        return generation
    }
    private func install(_ value: SessionRecord) throws {
        try persist(value)
        record = value; restored = true; generation = UUID()
        publish()
    }
    private func restore() throws {
        guard !restored else { return }
        do {
            if let data = try store.read() {
                let value = try JSONDecoder().decode(SessionRecord.self, from: data)
                guard !value.accessToken.isEmpty, !value.refreshToken.isEmpty else { throw AuthenticationError.storageUnavailable }
                record = value
            }
            if let data = try flowStore?.read() {
                pending = try JSONDecoder().decode(EmailFlow.self, from: data)
                if let pending, now().timeIntervalSince(pending.createdAt) > 3600 { try saveFlow(nil) }
            }
            restored = true
            publish()
        } catch { throw AuthenticationError.storageUnavailable }
    }
    private func persist(_ value: SessionRecord?) throws {
        do { try store.write(try value.map { try JSONEncoder().encode($0) }) }
        catch { throw AuthenticationError.storageUnavailable }
    }
    private func saveFlow(_ value: EmailFlow?) throws {
        if let value, flowStore == nil { _ = value; throw AuthenticationError.storageUnavailable }
        do { try flowStore?.write(try value.map { try JSONEncoder().encode($0) }) }
        catch { throw AuthenticationError.storageUnavailable }
        pending = value
        publish()
    }
    private func makeFlow(email: String, kind: EmailKind) throws -> EmailFlow {
        guard flowStore != nil else { throw AuthenticationError.storageUnavailable }
        // SystemRandomNumberGenerator uses the system cryptographic random source.
        let bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }
        let verifier = Data(bytes).base64URL
        return .init(id: UUID(), email: email, kind: kind, verifier: verifier, createdAt: now())
    }
    private func validateFlow(_ value: EmailFlow) throws {
        guard now().timeIntervalSince(value.createdAt) >= -60,
              now().timeIntervalSince(value.createdAt) <= 3600 else { throw AuthenticationError.emailFlowExpired }
    }
    private func validateEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !email.contains(where: \.isWhitespace) else { throw AuthenticationError.invalidEmail }
        return email
    }
    private func validatePassword(_ value: String) throws {
        guard value.count >= 8 else { throw AuthenticationError.weakPassword }
    }

    private func token<Body: Encodable>(grant: String, body: Body, recovery: Bool = false) async throws -> SessionRecord {
        do {
            let data = try await send("token", body: body, query: [.init(name: "grant_type", value: grant)])
            let value = try JSONDecoder().decode(TokenResponse.self, from: data)
            return try value.session(now: now(), recovery: recovery)
        } catch let error as AuthenticationError {
            if grant == "refresh_token", [.invalidCredentials, .emailNotConfirmed, .emailFlowExpired].contains(error) {
                throw AuthenticationError.sessionExpired
            }
            throw error
        } catch is DecodingError { throw AuthenticationError.invalidResponse }
    }
    private func send<Body: Encodable>(_ path: String, method: String = "POST", body: Body,
                                       token: String? = nil, redirect: URL? = nil, query: [URLQueryItem] = []) async throws -> Data {
        var query = query
        if let redirect { query.append(.init(name: "redirect_to", value: redirect.absoluteString)) }
        var request = connection.request(path: "auth/v1/" + path, query: query, token: token)
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await connection.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthenticationError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
            if path == "user", response.statusCode == 401 { throw AuthenticationError.sessionExpired }
            let payload = try? JSONDecoder().decode(AuthRejection.self, from: data)
            let code = payload?.error_code ?? payload?.code
            if path == "token", query.contains(.init(name: "grant_type", value: "id_token")) {
                if code == "provider_disabled" { throw AuthenticationError.appleSignInUnavailable }
                if [400, 401, 403, 422].contains(response.statusCode) { throw AuthenticationError.invalidAppleCredential }
            }
            throw Self.mapError(status: response.statusCode, code: code,
                                refreshing: path == "token" && query.contains(.init(name: "grant_type", value: "refresh_token")))
        }
        return data
    }
    private static func mapError(status: Int, code: String?, refreshing: Bool) -> AuthenticationError {
        if status == 429 { return .rateLimited }
        if refreshing && [400, 401, 403, 422].contains(status) { return .sessionExpired }
        switch code {
        case "email_not_confirmed": return .emailNotConfirmed
        case "weak_password": return .weakPassword
        case "same_password": return .passwordUnchanged
        case "email_address_invalid", "validation_failed": return .invalidEmail
        case "signup_disabled", "email_provider_disabled": return .signupUnavailable
        case "reauthentication_needed", "reauthentication_not_valid": return .reauthenticationRequired
        case "otp_expired", "flow_state_expired", "flow_state_not_found": return .emailFlowExpired
        case "bad_code_verifier", "bad_oauth_state": return .invalidCallback
        case "email_address_not_authorized", "email_send_failed": return .emailDeliveryFailed
        default:
            if [400, 401, 403, 422].contains(status) { return .invalidCredentials }
            return .server(status: status)
        }
    }
    private struct SessionRecord: Codable, Sendable {
        let account: TravellerAccount
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let recovery: Bool?
        var appleUserID: String? = nil
        var isRecovery: Bool { recovery == true }
    }
    private enum EmailKind: String, Codable { case signup, recovery }
    private struct EmailFlow: Codable, Sendable {
        let id: UUID
        let email: String
        let kind: EmailKind
        let verifier: String
        let createdAt: Date
        var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
        var redirect: URL {
            var components = URLComponents(url: SupabaseAuthentication.callbackURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [.init(name: "state", value: id.uuidString)]
            return components.url!
        }
    }
    private struct AppleToken: Encodable { let id_token: String; let nonce: String; let provider = "apple" }
    private struct Credentials: Encodable { let email: String; let password: String }
    private struct Signup: Encodable {
        let email: String; let password: String; let code_challenge: String
        let code_challenge_method = "s256"
    }
    private struct SignupUser: Decodable { let id: UUID }
    private struct Recover: Encodable { let email: String; let code_challenge: String; let code_challenge_method = "s256" }
    private struct Resend: Encodable {
        let email: String; let code_challenge: String
        let type = "signup"; let code_challenge_method = "s256"
    }
    private struct CodeExchange: Encodable { let auth_code: String; let code_verifier: String }
    private struct Password: Encodable { let password: String }
    private struct RefreshToken: Encodable { let refresh_token: String }
    private struct Empty: Encodable { }
    private struct AuthRejection: Decodable {
        let error_code: String?
        let code: String?
        enum CodingKeys: String, CodingKey { case error_code, code }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            error_code = try? values.decode(String.self, forKey: .error_code)
            // GoTrue also returns a numeric HTTP code; it must not discard error_code.
            code = try? values.decode(String.self, forKey: .code)
        }
    }
    private struct TokenResponse: Decodable {
        let access_token: String; let refresh_token: String; let token_type: String
        let expires_in: Double; let expires_at: Double?; let user: TravellerAccount
        func session(now: Date, recovery: Bool) throws -> SessionRecord {
            let expiry = expires_at.map { Date(timeIntervalSince1970: $0) } ?? now.addingTimeInterval(expires_in)
            guard token_type.lowercased() == "bearer", !access_token.isEmpty, !refresh_token.isEmpty,
                  expires_in > 60, expiry.timeIntervalSince(now) > 60 else { throw AuthenticationError.invalidResponse }
            return .init(account: user, accessToken: access_token, refreshToken: refresh_token, expiresAt: expiry, recovery: recovery)
        }
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
