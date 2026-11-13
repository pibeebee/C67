#if DEBUG
    import SwiftUI

    struct SavedTripDesignPreview: View {
        var completed = false
        @State private var notice = false
        var body: some View {
            NavigationStack {
                SavedItineraryContent(trip: TripDesignPreviewData.trip(status: completed ? .completed : .planned),
                                      details: ItineraryPreviewData.details, isDesignPreview: true,
                                      primary: { notice = true })
                    .alert("Design preview", isPresented: $notice) { Button("OK", role: .cancel) {} }
            }
        }
    }

    #Preview("ITINERARY LIST Copy · My Trip") { SavedTripDesignPreview() }
    #Preview("My Trip · Dark") { SavedTripDesignPreview().preferredColorScheme(.dark) }
    #Preview("Completed trip") { SavedTripDesignPreview(completed: true) }
#endif
