import SwiftUI
import C67Domain

struct TripProgressView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let trip = presenter.trips.first(where: { $0.id == tripID }) {
            TripProgressContent(trip: trip, isBusy: presenter.isBusy, error: presenter.error,
                                openDirections: {
                                    if let next = trip.nextStop { PlanningDirections.open(next, mode: trip.input.mode) }
                                }, arrive: { send(.arrive, trip: trip) },
                                completeVisit: { send(.completeStop, trip: trip) }, returnToTrip: { dismiss() })
                .refreshable { await presenter.load() }
        } else {
            ContentUnavailableView("Trip unavailable", systemImage: "map",
                                   description: Text("Return to Home and refresh your trips."))
        }
    }

    private func send(_ kind: PlanningEventKind, trip: PersonalPlanningTrip) {
        guard !presenter.isBusy else { return }
        Task { await presenter.event(kind, trip: trip) }
    }
}
