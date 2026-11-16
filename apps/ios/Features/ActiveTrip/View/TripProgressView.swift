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
            TripProgressContent(trip: trip, isBusy: presenter.isBusy, error: presenter.error,
                                route: navigation.route, locationError: navigation.error, locationPermissionDenied: navigation.permissionDenied,
                                openDirections: {
                                    if let next = trip.nextStop { navigation.start(to: next.location, mode: trip.input.mode) }
                                }, openSettings: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }, openMaps: {
                                    if let next = trip.nextStop { PlanningDirections.open(next, mode: trip.input.mode) }
                                }, arrive: { send(.arrive, trip: trip) },
                                completeVisit: { send(.completeStop, trip: trip) }, returnToTrip: { dismiss() })
                .refreshable { await presenter.load() }
                .task(id: trip.nextStop?.id) {
                    guard trip.status == .active, trip.currentStopID == nil, let stop = trip.nextStop else { navigation.stop(); return }
                    navigation.start(to: stop.location, mode: trip.input.mode)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, navigation.permissionDenied, let next = trip.nextStop, trip.currentStopID == nil {
                        navigation.start(to: next.location, mode: trip.input.mode)
                    }
                }
                .onChange(of: navigation.arrivalReady) { _, arrived in
                    if arrived, trip.currentStopID == nil, !presenter.isBusy {
                        navigation.stop()
                        send(.arrive, trip: trip)
                    }
                }
                .onChange(of: presenter.isBusy) { _, busy in
                    if !busy, navigation.arrivalReady, trip.currentStopID == nil {
                        navigation.stop()
                        send(.arrive, trip: trip)
                    }
                }
                .onChange(of: trip.currentStopID) { _, id in if id != nil { navigation.stop() } }
                .onDisappear { navigation.stop() }
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
