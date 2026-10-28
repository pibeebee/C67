import C67Domain

enum AccountAssembly {
    @MainActor static func makePresenter(authentication: any TravellerAuthentication) -> AccountPresenter {
        AccountPresenter(interactor: AccountInteractor(authentication: authentication))
    }
}
