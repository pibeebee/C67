import SwiftUI
import C67Domain

struct SavedTripView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @State private var showsProgress = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let trip = presenter.trips.first(where: { $0.id == tripID }) {
                SavedItineraryContent(trip: trip, isBusy: presenter.isBusy, error: presenter.error,
                                      primary: { primary(trip) })
                    .navigationDestination(isPresented: $showsProgress) {
                        TripProgressView(tripID: tripID, presenter: presenter)
                    }
                    .navigationDestination(for: SavedTripRoute.self) { _ in
                        ActivePlanningTripView(tripID: tripID, presenter: presenter)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: SavedTripRoute.options) {
                                Label("Trip options", systemImage: "ellipsis")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    .refreshable { await presenter.load() }
            } else {
                ContentUnavailableView("Trip unavailable", systemImage: "map",
                                       description: Text("Return to Home and refresh your trips."))
            }
        }
    }

    private func primary(_ trip: PersonalPlanningTrip) {
        guard !presenter.isBusy else { return }
        if trip.status == .completed { dismiss(); return }
        if trip.status == .active { showsProgress = true; return }
        guard trip.status == .planned else { return }
        Task {
            await presenter.event(.start, trip: trip)
            if !Task.isCancelled, presenter.trips.first(where: { $0.id == tripID })?.status == .active { showsProgress = true }
        }
    }
}
