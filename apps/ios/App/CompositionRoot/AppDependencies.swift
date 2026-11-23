import Foundation
import C67Domain
import C67Data
#if DEBUG
    import Synchronization
#endif

struct AppDependencies {
    static let authenticatedMode = "Pocket • authenticated"

    static var reviewEmails: Set<String> {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--pocket-review-fixture") { return ["review@example.test"] }
            if arguments.contains("--pocket-auth-fixture") { return [] }
        #endif
        let configured = Bundle.main.object(forInfoDictionaryKey: "TRAVELANTS_REVIEW_EMAILS") as? String ?? ""
        return Set(configured.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { $0.contains("@") })
    }

    @MainActor static func makeAuthenticated(removeAccountData: @escaping @Sendable (UUID) async throws -> Void) throws -> any TravellerAuthentication {
        let bundle = Bundle.main
        guard bundle.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String == "pocket-auth" else {
            throw RepositoryError.invalidConfiguration
        }
        let pocketURL = (bundle.object(forInfoDictionaryKey: "POCKET_SERVER_URL") as? String).flatMap(URL.init(string:))
        let deletion = AccountDeletionConfiguration(baseURL: pocketURL, removeLocalData: removeAccountData)
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_CLIENT_KEY") as? String, !key.isEmpty else {
            throw RepositoryError.invalidConfiguration
        }
        let auth = try SupabaseAuthentication(baseURL: url, clientKey: key,
                                              store: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".pocket-user", baseURL: url),
                                              flowStore: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".pocket-user-flow", baseURL: url),
                                              accountDeletion: deletion,
                                              passwordSignInAllowedEmails: AppDependencies.reviewEmails)
        return auth
    }

#if DEBUG
    let repository: any RundownRepository
    let planningRepository: any PlanningRepository
    let planningInitialInput: PlanningInput?
    let mode: String
    let authentication: (any TravellerAuthentication)?

    @MainActor static func make(removeAccountData: @escaping @Sendable (UUID) async throws -> Void) throws -> AppDependencies {
        let pocketURL = (Bundle.main.object(forInfoDictionaryKey: "POCKET_SERVER_URL") as? String).flatMap(URL.init(string:))
        let deletion = AccountDeletionConfiguration(baseURL: pocketURL, removeLocalData: removeAccountData)
        if ProcessInfo.processInfo.arguments.contains("--pocket-auth-fixture") {
            let url = URL(string: "https://fixture.invalid")!
            if ProcessInfo.processInfo.arguments.contains("--pocket-deletion-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--pocket-review-fixture") {
                let auth = try AccountDeletionFixture.makeAuthentication(baseURL: url, removeAccountData: removeAccountData)
                return .init(repository: try MockRundownRepository(), planningRepository: MockPlanningRepository(),
                             planningInitialInput: nil, mode: authenticatedMode, authentication: auth)
            }
            let auth = try SupabaseAuthentication(baseURL: url, clientKey: "synthetic-publishable-key",
                                                  store: KeychainSessionStore(namespace: "io.pibeebee.c67.pocket-auth-fixture", baseURL: url))
            return .init(repository: try MockRundownRepository(), planningRepository: MockPlanningRepository(),
                         planningInitialInput: nil, mode: authenticatedMode, authentication: auth)
        }
        if ProcessInfo.processInfo.arguments.contains("--pocket-runtime-acceptance") {
            let env = ProcessInfo.processInfo.environment
            guard let url = env["C67_LIVE_URL"], let token = env["C67_LIVE_READ_TOKEN"],
                  let encoded = env["C67_LIVE_INPUT"]?.data(using: .utf8), !token.isEmpty else {
                throw RepositoryError.invalidConfiguration
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let input = try decoder.decode(PlanningInput.self, from: encoded)
            let connection = RuntimePocketConnection(url: url, token: token)
            let repository = try PocketPlanningRepository(services: .live(connection: connection), connection: connection, storageURL: nil)
            return .init(repository: try MockRundownRepository(), planningRepository: repository, planningInitialInput: input,
                         mode: "Pocket • live runtime acceptance", authentication: nil)
        }
        if ProcessInfo.processInfo.arguments.contains("--pocket-integration-fixture") {
            let input = PocketIntegrationFixture.input()
            let lateJobTime = ProcessInfo.processInfo.arguments.contains("--pocket-late-day-fixture")
                ? PocketIntegrationFixture.lateDay() : nil
            let timesOut = ProcessInfo.processInfo.arguments.contains("--pocket-itinerary-timeout-fixture")
            let repository = try PocketIntegrationFixture.repository(jobClock: { lateJobTime ?? .now },
                                                                     firstOrderFailure: timesOut ? .timedOut : nil,
                                                                     externalAIDisclosure: ProcessInfo.processInfo.arguments.contains("--pocket-privacy-fixture") ? "fixture-v1" : nil,
                                                                     includesPinDetails: ProcessInfo.processInfo.arguments.contains("--itinerary-pin-details-fixture"))
            let initialInput = ProcessInfo.processInfo.arguments.contains("--without-starting-point") ? nil : input
            return .init(repository: try MockRundownRepository(), planningRepository: repository,
                         planningInitialInput: initialInput, mode: "Pocket • synthetic integration fixture", authentication: nil)
        }
        let mode = Bundle.main.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String ?? "mock"
        switch mode {
        case "pocket":
            let raw = Bundle.main.object(forInfoDictionaryKey: "POCKET_SERVER_URL") as? String ?? ""
            let endpoint = URL(string: raw)?.host == nil ? "" : raw
            let connection = PocketConnectionStore(serverURL: endpoint)
            let planning = try PocketPlanningRepository(services: .live(connection: connection), connection: connection,
                                                        storageURL: PocketPlanningRepository.defaultStorageURL())
            return .init(repository: try MockRundownRepository(), planningRepository: planning, planningInitialInput: nil,
                         mode: "Pocket • on-device", authentication: nil)
        case "mock":
            return .init(repository: try MockRundownRepository(), planningRepository: MockPlanningRepository(),
                         planningInitialInput: try MockPlanningRepository.sampleInput(),
                         mode: "Mock • memory only", authentication: nil)
        case "live":
            guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                  let url = URL(string: value),
                  let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_CLIENT_KEY") as? String else {
                throw RepositoryError.invalidConfiguration
            }
            let authentication = try SupabaseAuthentication(baseURL: url, clientKey: key,
                                                            store: KeychainSessionStore(namespace: Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter", baseURL: url),
                                                            flowStore: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".email-flow", baseURL: url),
                                                            accountDeletion: deletion)
            let planning: any PlanningRepository
            if let raw = Bundle.main.object(forInfoDictionaryKey: "PLANNING_API_URL") as? String,
               let endpoint = URL(string: raw), endpoint.host != nil {
                planning = try HTTPPlanningRepository(baseURL: endpoint, authentication: authentication,
                                                      onUnauthorized: { try await authentication.invalidateSession(rejectedToken: $0) })
            } else { planning = UnconfiguredPlanningRepository() }
            return .init(repository: try SupabaseRundownRepository(baseURL: url, clientKey: key,
                                                                   authentication: authentication,
                                                                   accessToken: { try await authentication.accessToken() },
                                                                   onUnauthorized: { try await authentication.invalidateSession(rejectedToken: $0) }),
                         planningRepository: planning, planningInitialInput: nil,
                         mode: "Live • Supabase", authentication: authentication)
        default: throw RepositoryError.invalidConfiguration
        }
    }
#endif
}

#if DEBUG
    /// Exercises the native account flow with an isolated Keychain namespace and synthetic HTTP responses.
    // Foundation controls URLProtocol callbacks; the only shared fixture state is protected by Mutex.
    private final class AccountDeletionFixture: URLProtocol, @unchecked Sendable {
        private static let accountID = UUID(uuidString: "ED93E5E7-46A8-4ACC-9C80-21328963F861")!
        private static let acceptedReceipt = Mutex<UUID?>(nil)

        static func makeAuthentication(baseURL: URL, removeAccountData: @escaping @Sendable (UUID) async throws -> Void) throws
            -> SupabaseAuthentication {
            let reviewFixture = ProcessInfo.processInfo.arguments.contains("--pocket-review-fixture")
            let namespace = reviewFixture ? "io.pibeebee.c67.review-ui-fixture" : "io.pibeebee.c67.deletion-ui-fixture"
            let store = KeychainSessionStore(namespace: namespace, baseURL: baseURL)
            if reviewFixture, ProcessInfo.processInfo.arguments.contains("--reset-review-fixture") {
                try store.write(nil)
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-deletion-fixture") {
                try store.write(JSONSerialization.data(withJSONObject: [
                    "account": ["id": accountID.uuidString, "email": "deletion@example.test"],
                    "accessToken": "synthetic-deletion-access",
                    "refreshToken": "synthetic-deletion-refresh",
                    "expiresAt": Date.now.addingTimeInterval(3600).timeIntervalSinceReferenceDate
                ]))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [Self.self]
            return try SupabaseAuthentication(baseURL: baseURL, clientKey: "synthetic-publishable-key", store: store,
                                              session: URLSession(configuration: configuration),
                                              accountDeletion: .init(baseURL: baseURL, removeLocalData: removeAccountData),
                                              passwordSignInAllowedEmails: AppDependencies.reviewEmails)
        }

        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, request.httpMethod == "POST" else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if url.path == "/auth/v1/token", url.query == "grant_type=password",
               ProcessInfo.processInfo.arguments.contains("--pocket-review-fixture") {
                handleReviewSignIn()
                return
            }
            guard url.path == "/v1/account/deletion",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-deletion-access",
                  let body = try? JSONDecoder().decode(DeletionBody.self, from: requestBody()) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let (status, json) = Self.acceptedReceipt.withLock { receipt in
                if receipt == body.requestID { return (200, #"{"status":"deleted"}"#) }
                let isReviewFixture = ProcessInfo.processInfo.arguments.contains("--pocket-review-fixture")
                if receipt == nil, isReviewFixture || body.useManualAppleRevocation == true ||
                    body.appleAuthorizationCode == "synthetic-deletion-code" {
                    receipt = body.requestID
                    return (202, #"{"status":"pending"}"#)
                }
                return (409, #"{"code":"APPLE_VERIFICATION_REQUIRED"}"#)
            }
            respond(status, json)
        }

        private func handleReviewSignIn() {
            guard let body = try? JSONDecoder().decode(ReviewCredentials.self, from: requestBody()),
                  body.email == "review@example.test", body.password == "synthetic-review-password" else {
                respond(400, #"{"error_code":"invalid_credentials"}"#)
                return
            }
            respond(200, """
            {"access_token":"synthetic-deletion-access","refresh_token":"synthetic-review-refresh","token_type":"bearer",
             "expires_in":3600,"user":{"id":"\(Self.accountID.uuidString)","email":"review@example.test"}}
            """)
        }

        private func respond(_ status: Int, _ json: String) {
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                                       headerFields: ["Content-Type": "application/json"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func requestBody() -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { return data }
                data.append(contentsOf: buffer.prefix(count))
            }
        }

        private struct DeletionBody: Decodable {
            let requestID: UUID
            let appleAuthorizationCode: String?
            let useManualAppleRevocation: Bool?
        }

        private struct ReviewCredentials: Decodable {
            let email: String
            let password: String
        }
    }

    // Opt-in harness: public selected pins are inputs; all visit facts, Luna and ETA remain live.
    private struct RuntimePocketConnection: PocketConnectionProviding {
        let url: String
        let token: String
        func credentials() async -> PocketCredentials { .init(serverURL: url, token: token) }
        func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
    }
#endif
