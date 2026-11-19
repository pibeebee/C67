import SwiftUI
import C67Domain

struct SavedTripView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @State private var showsProgress = false
    @State private var preparedStart: PlanningStartPreparation?
    @State private var showsStartConfirmation = false
    @State private var showsDateEditor = false
    @State private var showsDateReview = false
    @State private var replacementDeparture = Date()
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let trip = presenter.trips.first(where: { $0.id == tripID }) {
                let issue = presenter.issues[.savedTrip(tripID)] ?? presenter.issues[.planning(tripID)] ?? startIssue
                SavedItineraryContent(trip: trip, isBusy: presenter.isBusy, error: issue?.message,
                                      retry: recovery(for: issue, trip: trip),
                                      refreshRoute: trip.status == .planned && trip.plan.hasExperienceTravelFallback ? { refreshRoute() } : nil,
                                      primary: { primary(trip) })
                    .navigationDestination(isPresented: $showsProgress) {
                        TripProgressView(tripID: tripID, presenter: presenter)
                    }
                    .navigationDestination(for: SavedTripRoute.self) { _ in
                        ActivePlanningTripView(tripID: tripID, presenter: presenter, startTrip: { primary(trip) })
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                NavigationLink("Trip options", value: SavedTripRoute.options)
                                if trip.status == .planned, trip.plan.effectiveOrderingMethod.usesFlexibleSchedule {
                                    Button("Change trip date") { editDate(trip) }
                                    if presenter.job?.tripID == trip.id, presenter.job?.baseRevision == trip.revision,
                                       presenter.job?.command?.replacementDeparture != nil,
                                       presenter.job?.result?.proposal?.feasible == true {
                                        Button("Review revised schedule") { showDateReviewIfReady(trip) }
                                    }
                                }
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
                    .sheet(isPresented: $showsStartConfirmation) {
                        if let preparation = preparedStart {
                            NavigationStack {
                                ItineraryListView(proposal: preparation.proposal, actionTitle: "Start with this schedule",
                                                  allowsEditing: false, edit: { _ in }, save: {
                                                      showsStartConfirmation = false
                                                      start(trip, preparationID: preparation.id)
                                                  })
                                                  .toolbar {
                                                      ToolbarItem(placement: .cancellationAction) {
                                                          Button("Cancel") {
                                                              preparedStart = nil
                                                              showsStartConfirmation = false
                                                          }
                                                      }
                                                  }
                            }
                        }
                    }
                    .sheet(isPresented: $showsDateEditor) {
                        NavigationStack {
                            Form {
                                DatePicker("Departure", selection: $replacementDeparture)
                                Button("Calculate schedule") {
                                    showsDateEditor = false
                                    Task {
                                        await requestDateRevision(trip)
                                    }
                                }
                            }
                            .environment(\.timeZone, TimeZone(identifier: trip.input.timeZone) ?? .current)
                            .navigationTitle("Change trip date")
                        }
                    }
                    .sheet(isPresented: $showsDateReview) {
                        if let proposal = presenter.job?.result?.proposal, presenter.job?.tripID == trip.id {
                            NavigationStack {
                                ItineraryListView(proposal: proposal, isSaving: presenter.isBusy,
                                                  error: presenter.issues[.savedTrip(trip.id)]?.message,
                                                  actionTitle: "Apply schedule", allowsEditing: false,
                                                  edit: { _ in }, save: {
                                                      Task {
                                                          await presenter.apply(scope: .savedTrip(trip.id))
                                                          if presenter.issues[.savedTrip(trip.id)] == nil { showsDateReview = false }
                                                      }
                                                  })
                            }
                        }
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
        if issue.cause == .planning(.failed("START_DATE_MISMATCH")) { return { editDate(trip) } }
        if issue.recovery == .checkStatus {
            return { Task {
                await presenter.checkStatus(scope: .planning(trip.id))
                showDateReviewIfReady(trip)
            } }
        }
        if issue.recovery == .refreshTrip { return { Task { await presenter.load(resumesJobs: false) } } }
        guard issue.recovery == .retry else { return nil }
        switch issue.operation {
        case .plan(.replan): return { editDate(trip) }
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
            do {
                let preparation = try await presenter.prepareStart(trip)
                if let preparation, preparation.scheduleChanged {
                    preparedStart = preparation
                    showsStartConfirmation = true
                } else {
                    start(trip, preparationID: preparation?.id)
                }
            } catch { }
        }
    }

    private func start(_ trip: PersonalPlanningTrip, preparationID: UUID?) {
        Task {
            await presenter.event(.start, trip: trip, preparationID: preparationID)
            if !Task.isCancelled, presenter.trips.first(where: { $0.id == tripID })?.status == .active { showsProgress = true }
        }
    }

    private func editDate(_ trip: PersonalPlanningTrip) {
        replacementDeparture = max(.now, trip.plan.departureAt ?? trip.plan.input.startsAt)
        showsDateEditor = true
    }

    private func requestDateRevision(_ trip: PersonalPlanningTrip) async {
        await presenter.request(.replan, trip: trip, replacementDeparture: replacementDeparture)
        showDateReviewIfReady(trip)
    }

    private func showDateReviewIfReady(_ trip: PersonalPlanningTrip) {
        if presenter.job?.tripID == trip.id, presenter.job?.baseRevision == trip.revision,
           presenter.job?.result?.proposal?.feasible == true {
            showsDateReview = true
        }
    }
}
