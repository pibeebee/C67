import SwiftUI
import C67Domain

struct SavedTripView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @State private var showsProgress = false
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let trip = presenter.trips.first(where: { $0.id == tripID }) {
                let issue = presenter.issues[.savedTrip(tripID)] ?? startIssue
                SavedItineraryContent(trip: trip, isBusy: presenter.isBusy, error: issue?.message,
                                      retry: recovery(for: issue, trip: trip),
                                      refreshRoute: trip.status == .planned && trip.plan.hasExperienceTravelFallback ? { refreshRoute() } : nil,
                                      primary: { primary(trip) })
                    .navigationDestination(isPresented: $showsProgress) {
                        TripProgressView(tripID: tripID, presenter: presenter)
                    }
                    .navigationDestination(for: SavedTripRoute.self) { _ in
                        ActivePlanningTripView(tripID: tripID, presenter: presenter)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                NavigationLink("Trip options", value: SavedTripRoute.options)
                                if presenter.supportsTripDeletion {
                                    Button("Delete trip", role: .destructive) { confirmsDelete = true }
                                }
                            } label: {
                                Label("Trip options", systemImage: "ellipsis")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    .confirmationDialog("Delete this trip?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                        Button("Delete trip", role: .destructive) {
                            Task { if await presenter.deleteTrip(trip) { dismiss() } }
                        }
                    } message: {
                        Text("This removes the trip from this device and cannot be undone.")
                    }
                    .task {
                        if presenter.consumeStartRequest(for: tripID) { primary(trip) }
                        else if trip.status == .planned, trip.plan.usesExperienceFlow, trip.plan.experienceRouteCheckedAt == nil {
                            await presenter.refreshSavedExperienceRoute(tripID: tripID)
                        }
                    }
                    .refreshable { await presenter.load(resumesJobs: false) }
            } else {
                ContentUnavailableView {
                    Label("Trip unavailable", systemImage: "map")
                } description: {
                    Text("Return to Home and refresh your trips.")
                } actions: {
                    Button("Return to Home") { dismiss() }
                }
            }
        }
    }

    private var startIssue: PresentationIssue? {
        guard let issue = presenter.issues[.activity(tripID)], case .event(.start, _) = issue.operation else { return nil }
        return issue
    }

    private func recovery(for issue: PresentationIssue?, trip: PersonalPlanningTrip) -> (() -> Void)? {
        guard let issue else { return nil }
        if issue.recovery == .refreshTrip { return { Task { await presenter.load(resumesJobs: false) } } }
        guard issue.recovery == .retry else { return nil }
        switch issue.operation {
        case .refreshSavedRoute: return { refreshRoute() }
        case .delete: return { confirmsDelete = true }
        case .event(.start, _): return { primary(trip) }
        default: return nil
        }
    }

    private func refreshRoute() {
        Task { await presenter.refreshSavedExperienceRoute(tripID: tripID) }
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
