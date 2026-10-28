import Foundation
import C67Domain
import C67Data

struct AppDependencies {
    let repository: any RundownRepository
    let mode: String
    let authentication: (any TravellerAuthentication)?

    @MainActor static func make() throws -> AppDependencies {
        let mode = Bundle.main.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String ?? "mock"
        switch mode {
        case "mock":
            return .init(repository: try MockRundownRepository(), mode: "Mock • memory only", authentication: nil)
        case "live":
            guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                  let url = URL(string: value),
                  let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_CLIENT_KEY") as? String else {
                throw RepositoryError.invalidConfiguration
            }
            let authentication = try SupabaseAuthentication(baseURL: url, clientKey: key,
                                                            store: KeychainSessionStore(namespace: Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter", baseURL: url),
                                                            flowStore: KeychainSessionStore(namespace: (Bundle.main.bundleIdentifier ?? "io.pibeebee.c67.starter") + ".email-flow", baseURL: url))
            return .init(repository: try SupabaseRundownRepository(baseURL: url, clientKey: key,
                                                                   authentication: authentication,
                                                                   accessToken: { try await authentication.accessToken() },
                                                                   onUnauthorized: { try await authentication.invalidateSession(rejectedToken: $0) }),
                         mode: "Live • Supabase", authentication: authentication)
        default: throw RepositoryError.invalidConfiguration
        }
    }
}
