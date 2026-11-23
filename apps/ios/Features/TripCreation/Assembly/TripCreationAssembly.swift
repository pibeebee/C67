import SwiftUI
#if DEBUG
    import C67Data
    import C67Domain
#endif

@MainActor enum TripCreationAssembly {
    static func make(planning: PlanningPresenter, mode: String, specificPlace: Bool, dismiss: @escaping () -> Void) -> some View {
        let presenter = makePresenter(planning: planning, mode: mode, specificPlace: specificPlace)
        return TripCreationView(presenter: presenter, dismiss: dismiss)
    }

    static func makePresenter(planning: PlanningPresenter, mode: String, specificPlace: Bool) -> TripCreationPresenter {
        #if DEBUG
            if mode == "Pocket • synthetic integration fixture" {
                let testsOrderingTimeout = ProcessInfo.processInfo.arguments.contains("--pocket-itinerary-timeout-fixture")
                let arguments = ProcessInfo.processInfo.arguments
                let fixtureMethod = arguments.firstIndex(of: "-io.pibeebee.c67.orderingMethod")
                    .flatMap { arguments.dropFirst($0 + 1).first }
                    .flatMap(PlanningOrderingMethod.init(rawValue:))
                let lateDate = ProcessInfo.processInfo.arguments.contains("--pocket-late-day-fixture") ? PocketIntegrationFixture.lateDay() : nil
                return TripCreationPresenter(planning: planning, mode: mode, specificPlace: specificPlace,
                                             interactor: .init(searcher: PocketFixtureTripPlaceSearch()),
                                             orderingMethod: { testsOrderingTimeout ? .luna : (fixtureMethod ?? .hybridV52) }, clock: { lateDate ?? .now })
            }
            let searcher: any TripPlaceSearching = mode.hasPrefix("Mock") ? SyntheticTripPlaceSearch() : MapKitTripPlaceSearch()
        #else
            let searcher = MapKitTripPlaceSearch()
        #endif
        return TripCreationPresenter(planning: planning, mode: mode, specificPlace: specificPlace,
                                     interactor: .init(searcher: searcher))
    }
}
