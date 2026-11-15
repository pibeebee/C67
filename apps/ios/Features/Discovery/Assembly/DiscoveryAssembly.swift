import SwiftUI
import C67Domain

enum DiscoveryAssembly {
    @MainActor static func make(repository: any RundownRepository, mode: String,
                                authentication: (any TravellerAuthentication)? = nil) -> some View {
        let presenter = DiscoveryPresenter(interactor: .init(repository: repository))
        let account = authentication.map { AccountAssembly.makePresenter(authentication: $0) }
        account?.onSessionChange = { [weak presenter] snapshot in presenter?.sessionDidChange(snapshot) }
        return DiscoveryView(presenter: presenter, mode: mode, accountPresenter: account)
    }
}
