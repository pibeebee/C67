import SwiftUI
import C67Domain

struct SavedItineraryContent: View {
    let trip: PersonalPlanningTrip
    var details: [UUID: ItineraryStopDetails] = [:]
    var isDesignPreview = false
    var isBusy = false
    var error: String?
    var retry: (() -> Void)?
    var refreshRoute: (() -> Void)?
    var lookupHours: ((String) async -> PlanningHoursLookup)?
    let primary: () -> Void

    private var actionTitle: String {
        switch trip.status {
        case .planned: "Go Trip"
        case .active: "Continue trip"
        case .completed: "Back to trips"
        case .unknown: "Trip unavailable"
        }
    }

    var body: some View {
        ItineraryListView(proposal: trip.plan, details: details, isDesignPreview: isDesignPreview,
                          isSaving: isBusy, error: error, canSave: trip.status != .unknown,
                          heading: trip.title, actionTitle: actionTitle,
                          completionMessage: trip.status == .completed ? "All \(trip.completedStopIDs.count) visits completed" : nil,
                          showsPreparation: trip.status == .planned,
                          allowsEditing: false, navigationTitle: trip.title,
                          retry: retry, refreshRoute: refreshRoute, lookupHours: lookupHours, edit: { _ in }, save: primary)
            .navigationTitle(trip.title)
    }
}
