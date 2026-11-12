#if DEBUG
    import SwiftUI

    struct ItineraryDesignPreview: View {
        @State private var showsNotice = false

        var body: some View {
            NavigationStack {
                ItineraryListView(proposal: ItineraryPreviewData.proposal, details: ItineraryPreviewData.details,
                                  departureWeather: "32° · Bring water for the walk", isDesignPreview: true,
                                  edit: { _ in showsNotice = true }, save: { showsNotice = true },
                                  move: { _, _ in showsNotice = true })
                    .toolbar(.hidden, for: .navigationBar)
                    .alert("Design preview", isPresented: $showsNotice) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("This screen contains the supplied Sketch sample. To edit and save a trip, open the app normally and plan your own itinerary.")
                    }
            }
        }
    }

    #Preview("ITINERARY LIST") {
        ItineraryDesignPreview()
    }
#endif
