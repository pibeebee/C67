#if DEBUG
    import Foundation
    import C67Domain

    enum TripDesignPreviewData {
        static func trip(status: PersonalTripStatus = .planned, arrived: Bool = false) -> PersonalPlanningTrip {
            var input = ItineraryPreviewData.input
            input.title = "My Trip"
            return .init(id: UUID(), title: "My Trip", revision: 1, status: status, input: input,
                         plan: ItineraryPreviewData.proposal,
                         completedStopIDs: status == .completed ? ItineraryPreviewData.ids : [],
                         currentStopID: arrived ? ItineraryPreviewData.ids[0] : nil,
                         currentArrivedAt: arrived ? ItineraryPreviewData.startsAt : nil,
                         synthetic: true, createdAt: ItineraryPreviewData.startsAt)
        }
    }
#endif
