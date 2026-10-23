import Foundation
import C67Domain
import C67Data

struct AppDependencies {
    let repository: any RundownRepository
    let mode: String

    @MainActor static func make() throws -> AppDependencies {
        let mode = Bundle.main.object(forInfoDictionaryKey: "C67_DATA_MODE") as? String ?? "mock"
        switch mode {
        case "mock":
            return .init(repository: try MockRundownRepository(), mode: "Mock • memory only")
        case "live":
            guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                  let url = URL(string: value),
                  let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_CLIENT_KEY") as? String else {
                throw RepositoryError.invalidConfiguration
            }
            // Replace this provider with a secure, refreshed traveller session in the Auth task.
            return .init(repository: try SupabaseRundownRepository(baseURL: url, clientKey: key),
                         mode: "Live catalog • sign-in pending")
        default: throw RepositoryError.invalidConfiguration
        }
    }
}
