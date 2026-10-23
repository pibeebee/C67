import SwiftUI
import C67Domain

enum DiscoveryAssembly {
    @MainActor static func make(repository: any RundownRepository, mode: String) -> some View {
        DiscoveryView(presenter: DiscoveryPresenter(interactor: .init(repository: repository)), mode: mode)
    }
}
