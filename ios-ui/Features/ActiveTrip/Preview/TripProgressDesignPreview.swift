#if DEBUG
    import SwiftUI

    struct TripProgressDesignPreview: View {
        var arrived = false
        @State private var notice = false
        var body: some View {
            NavigationStack {
                TripProgressContent(trip: TripDesignPreviewData.trip(status: .active, arrived: arrived),
                                    details: ItineraryPreviewData.details, isDesignPreview: true,
                                    previewInstruction: "80 m", previewDistance: "450 m",
                                    openDirections: { notice = true }, arrive: { notice = true },
                                    completeVisit: { notice = true }, returnToTrip: { notice = true })
                    .alert("Design preview", isPresented: $notice) { Button("OK", role: .cancel) {} } message: {
                        Text("Sample map and estimates. No live guidance or trip event is recorded.")
                    }
            }
        }
    }
    #Preview("TRIP STARTED") { TripProgressDesignPreview() }
    #Preview("TRIP DONE · Arrival") { TripProgressDesignPreview(arrived: true) }
    #Preview("Arrival · Dark, large text") {
        TripProgressDesignPreview(arrived: true).preferredColorScheme(.dark).dynamicTypeSize(.accessibility3)
    }
#endif
