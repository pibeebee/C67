#if DEBUG
    import SwiftUI

    struct ItinerarySaveDesignPreview: View {
        @State private var showsName = true
        @State private var name = "My Trip"
        var body: some View {
            NavigationStack {
                ItineraryListView(proposal: ItineraryPreviewData.proposal, details: ItineraryPreviewData.details,
                                  departureWeather: "32° · Bring water for the walk", isDesignPreview: true,
                                  edit: { _ in }, save: { showsName = true })
                    .modifier(ItinerarySaveNameDialog(isPresented: $showsName, name: $name, originalName: "My Trip", save: {}))
            }
        }
    }
    #Preview("ITINERARY LIST SAVE · Name dialog") { ItinerarySaveDesignPreview() }
#endif
