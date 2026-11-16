import Foundation
import C67Domain
import C67Data

struct AppDependencies {
    let repository: any RundownRepository
    let planningRepository: any PlanningRepository
    let planningInitialInput: PlanningInput?
    let mode: String
    let authentication: (any TravellerAuthentication)?

    @MainActor static func make() throws -> AppDependencies {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--pocket-auth-fixture") {
                let url = URL(string: "https://fixture.invalid")!
                let auth = try SupabaseAuthentication(baseURL: url, clientKey: "synthetic-publishable-key",
                                                      store: KeychainSessionStore(namespace: "io.pibeebee.c67.pocket-auth-fixture", baseURL: url))
                return .init(repository: try MockRundownRepository(), planningRepository: MockPlanningRepository(),
                             planningInitialInput: nil, mode: "Pocket • authenticated", authentication: auth)
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
                return .init(repository: try MockRundownRepository(), planningRepository: try PocketIntegrationFixture.repository(),
                             planningInitialInput: PocketIntegrationFixture.input(), mode: "Pocket • synthetic integration fixture", authentication: nil)
            }
        #endif
        let mode = Bundle.main.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String ?? "mock"
        switch mode {
        case "pocket-auth":
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                  let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_CLIENT_KEY") as? String, !key.isEmpty else {
                throw RepositoryError.invalidConfiguration
            }
            let auth = try SupabaseAuthentication(baseURL: url, clientKey: key,
                                                  store: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".pocket-user", baseURL: url),
                                                  flowStore: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".pocket-user-flow", baseURL: url))
            return .init(repository: try MockRundownRepository(), planningRepository: MockPlanningRepository(),
                         planningInitialInput: nil, mode: "Pocket • authenticated", authentication: auth)
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
                                                            flowStore: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".email-flow", baseURL: url))
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
}

#if DEBUG
    // Opt-in harness: public selected pins are inputs; all visit facts, Luna and ETA remain live.
    private struct RuntimePocketConnection: PocketConnectionProviding {
        let url: String
        let token: String
        func credentials() async -> PocketCredentials { .init(serverURL: url, token: token) }
        func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
    }
#endif
