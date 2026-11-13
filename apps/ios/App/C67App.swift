import SwiftUI

@main
struct C67App: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--add-places-preview") {
                    AddPlacesDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--add-places-selected-preview") {
                    AddPlacesDesignPreview(addedCount: 4)
                } else if ProcessInfo.processInfo.arguments.contains("--places-sheet-preview") {
                    AddPlacesDesignPreview(addedCount: 4, showsSheet: true)
                } else if ProcessInfo.processInfo.arguments.contains("--arrival-preview") {
                    TripProgressDesignPreview(arrived: true)
                } else if ProcessInfo.processInfo.arguments.contains("--active-trip-preview") {
                    TripProgressDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--home-added-preview") {
                    HomeAddedTripDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--saved-trip-preview") {
                    SavedTripDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--save-name-preview") {
                    ItinerarySaveDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--itinerary-preview") {
                    ItineraryDesignPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-preview") {
                    RecommendationsDesignPreview(addedCount: 0)
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-added-preview") {
                    RecommendationsDesignPreview(addedCount: 3)
                } else if ProcessInfo.processInfo.arguments.contains("--recommendations-processing-preview") {
                    RecommendationsProcessingView()
                } else {
                    StarterRootView()
                        .splashOverlay()
                }
            #else
                StarterRootView()
                    .splashOverlay()
            #endif
        }
    }
}

private struct StarterRootView: View {
    @State private var result = Result { try AppDependencies.make() }
    var body: some View {
        switch result {
        case .success(let dependencies):
            if ProcessInfo.processInfo.arguments.contains("--legacy-catalog") {
                DiscoveryAssembly.make(repository: dependencies.repository, mode: dependencies.mode,
                                       authentication: dependencies.authentication)
            } else {
                PlanningAssembly.make(repository: dependencies.planningRepository, mode: dependencies.mode,
                                      initialInput: dependencies.planningInitialInput,
                                      authentication: dependencies.authentication)
            }
        case .failure(let error):
            ContentUnavailableView("Configuration needed", systemImage: "gearshape",
                                   description: Text(error.localizedDescription))
        }
    }
}
