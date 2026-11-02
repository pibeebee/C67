import SwiftUI
import C67Domain

enum PlanningAssembly {
    @MainActor static func make(repository: any PlanningRepository, mode: String, initialInput: PlanningInput?,
                                authentication: (any TravellerAuthentication)?) -> some View {
        let presenter = PlanningPresenter(interactor: .init(repository: repository), initialInput: initialInput)
        let account = authentication.map { AccountAssembly.makePresenter(authentication: $0) }
        account?.onSessionChange = { [weak presenter] snapshot in
            guard let presenter else { return }
            presenter.sessionDidChange(snapshot)
        }
        return PlanningRootView(presenter: presenter, mode: mode, accountPresenter: account)
    }
}
