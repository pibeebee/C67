import SwiftUI
import C67Domain

struct SavedItineraryContent: View {
    let trip: PersonalPlanningTrip
    var details: [UUID: ItineraryStopDetails] = [:]
    var isDesignPreview = false
    var isBusy = false
    var error: String?
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
                          heading: trip.title, actionTitle: actionTitle, allowsEditing: false, navigationTitle: trip.title,
                          edit: { _ in }, save: primary)
            .navigationTitle(trip.title)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if trip.status == .completed {
                    Label("All \(trip.completedStopIDs.count) visits completed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).padding().frame(maxWidth: .infinity).background(AppColor.surface)
                }
            }
    }
}
