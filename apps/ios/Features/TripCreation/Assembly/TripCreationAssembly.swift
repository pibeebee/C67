import SwiftUI

@MainActor enum TripCreationAssembly {
    static func make(planning: PlanningPresenter, mode: String, specificPlace: Bool, dismiss: @escaping () -> Void) -> some View {
        let presenter = makePresenter(planning: planning, mode: mode, specificPlace: specificPlace)
        return TripCreationView(presenter: presenter, dismiss: dismiss)
    }

    static func makePresenter(planning: PlanningPresenter, mode: String, specificPlace: Bool) -> TripCreationPresenter {
        let searcher: any TripPlaceSearching = mode.hasPrefix("Mock") ? SyntheticTripPlaceSearch() : MapKitTripPlaceSearch()
        return TripCreationPresenter(planning: planning, mode: mode, specificPlace: specificPlace,
                                     interactor: .init(searcher: searcher))
    }
}
