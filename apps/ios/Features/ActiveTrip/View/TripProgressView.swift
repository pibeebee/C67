import SwiftUI
import UIKit
import C67Domain

struct TripProgressView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = TripNavigation()

    var body: some View {
        if let trip = presenter.trips.first(where: { $0.id == tripID }) {
            let issue = presenter.issues[.activity(tripID)]
            let target = trip.pendingEndpoint ?? trip.nextStop?.location
            TripProgressContent(trip: trip, isBusy: presenter.isBusy, error: issue?.message,
                                recovery: recovery(for: issue, trip: trip),
                                route: navigation.route, locationError: navigation.error, locationPermissionDenied: navigation.permissionDenied,
                                openDirections: {
                                    if let target { navigation.start(to: target, mode: trip.input.mode) }
                                }, openSettings: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }, openMaps: {
                                    if let endpoint = trip.pendingEndpoint {
                                        let name = trip.plan.input.enginePreferences?.endPointName ?? String(localized: "Starting point")
                                        PlanningDirections.open(endpoint, name: name, mode: trip.input.mode)
                                    } else if let next = trip.nextStop {
                                        PlanningDirections.open(next, mode: trip.input.mode)
                                    }
                                }, arrive: { send(.arrive, trip: trip) },
                                arriveAtEndpoint: { send(.arriveAtEndpoint, trip: trip) },
                                completeVisit: { send(.completeStop, trip: trip) }, returnToTrip: { dismiss() })
                .refreshable { await presenter.load(resumesJobs: false) }
                .task(id: trip.revision) { startNavigation(trip, target: target) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { startNavigation(trip, target: target) }
                    else { navigation.stop() }
                }
                .onChange(of: navigation.arrivalReady) { _, ready in
                    if ready { confirmAutomaticArrival(trip, target: target) }
                }
                .onChange(of: presenter.isBusy) { _, busy in
                    if !busy { confirmAutomaticArrival(trip, target: target) }
                }
                .onDisappear { navigation.stop() }
        } else {
            ContentUnavailableView {
                Label("Trip unavailable", systemImage: "map")
            } description: {
                Text("Return to Home and refresh your trips.")
            } actions: {
                Button("Go back") { dismiss() }
            }
        }
    }

    private func startNavigation(_ trip: PersonalPlanningTrip, target: PlanningPoint?) {
        guard scenePhase == .active, trip.status == .active, trip.currentStopID == nil, let target else {
            navigation.stop()
            return
        }
        navigation.start(to: target, mode: trip.input.mode)
    }

    private func confirmAutomaticArrival(_ trip: PersonalPlanningTrip, target: PlanningPoint?) {
        guard scenePhase == .active, !presenter.isBusy, let target,
              navigation.canConfirmArrival(at: target),
              presenter.trips.first(where: { $0.id == trip.id })?.revision == trip.revision else { return }
        let kind: PlanningEventKind = trip.pendingEndpoint == nil ? .arrive : .arriveAtEndpoint
        if kind == .arrive, !presenter.claimAutomaticArrival(for: trip) { return }
        navigation.stop()
        send(kind, trip: trip)
    }

    private func recovery(for issue: PresentationIssue?, trip: PersonalPlanningTrip) -> RecoveryNotice.Action? {
        guard let issue else { return nil }
        if issue.recovery == .refreshTrip {
            return .init(title: "Refresh trip") { Task { await presenter.load(resumesJobs: false) } }
        }
        guard issue.recovery == .retry, issue.stopID == trip.nextStop?.id,
              case .event(let kind, _) = issue.operation else { return nil }
        return .init(title: "Try again") { send(kind, trip: trip) }
    }

    private func send(_ kind: PlanningEventKind, trip: PersonalPlanningTrip) {
        guard !presenter.isBusy else { return }
        Task { await presenter.event(kind, trip: trip) }
    }
}
