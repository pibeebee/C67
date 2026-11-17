import SwiftUI

struct TripCreationView: View {
    @State private var presenter: TripCreationPresenter
    let dismiss: () -> Void
    let openPocketSettings: (() -> Void)?
    @State private var isRunningOperation = false
    @State private var operation: Task<Void, Never>?
    @State private var showsStartingPointSearch = false
    @State private var showsScheduleOptions = false

    init(presenter: TripCreationPresenter, dismiss: @escaping () -> Void, openPocketSettings: (() -> Void)? = nil) {
        _presenter = State(initialValue: presenter)
        self.dismiss = dismiss
        self.openPocketSettings = openPocketSettings
    }

    var body: some View {
        NavigationStack(path: $presenter.path) {
            screen(presenter.root)
                .navigationDestination(for: TripCreationRoute.self) { screen($0) }
        }
        .fullScreenCover(isPresented: Binding(get: { presenter.isProcessing }, set: { _ in })) {
            ZStack(alignment: .bottom) {
                TripProcessingView(advances: false, isReady: presenter.isShowingCompletion)
                if !presenter.isShowingCompletion {
                    Button { operation?.cancel(); dismiss() } label: {
                        Text(presenter.planning.supportsOnDevicePlanning ? "Continue later" : "Cancel")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .padding(20)
                }
            }
            .interactiveDismissDisabled()
        }
        .interactiveDismissDisabled(presenter.isProcessing || presenter.planning.isBusy)
        .onChange(of: presenter.planning.sessionGeneration) { _, _ in
            operation?.cancel(); presenter.cancelRecommendations(); dismiss()
        }
        .onDisappear { operation?.cancel(); presenter.cancelRecommendations() }
        .task {
            if presenter.route == .mainSpot, presenter.checksExistingRequest { run { await presenter.plan() } }
        }
        .sheet(isPresented: $showsScheduleOptions) {
            PocketScheduleOptionsSheet(presenter: presenter)
        }
        .sheet(isPresented: $showsStartingPointSearch) {
            PlanningSearchSheet(near: presenter.planning.origin, title: "Starting point") { place in
                presenter.planning.origin = place.location
                presenter.planning.originLabel = place.name
                presenter.planning.draftChanged()
                run { await presenter.plan() }
            }
        }
        .tint(AppColor.accent)
    }

    @ViewBuilder private func screen(_ route: TripCreationRoute) -> some View {
        Group {
            switch route {
            case .question(let step):
                PreferenceQuestionView(step: step, answers: presenter.answers,
                                       update: { presenter.answers = $0 },
                                       advance: { presenter.advance(step) },
                                       skip: { presenter.advance(step, skip: true) },
                                       refinementOptions: presenter.planning.preferenceLabels)
            case .places:
                AddPlacesView(query: $presenter.query, results: presenter.results, selected: presenter.selected,
                              isSearching: presenter.isSearching, error: presenter.searchError,
                              synthetic: presenter.mode.hasPrefix("Mock"), origin: presenter.planning.origin, search: { await presenter.search() }, toggle: presenter.toggle) {
                    if presenter.path.contains(.recommendations) { presenter.path.removeLast() }
                    else { presenter.finishChoosingPlaces() }
                }
            case .availability:
                PocketVisitAvailabilityView(presenter: presenter) { run { await presenter.plan() } }
            case .recommendations:
                PlacesRecommendationsView(batch: presenter.batch, selected: presenter.selected,
                                          isLoading: presenter.isSuggesting, error: presenter.recommendationError,
                                          areaDescription: TripDiscoveryArea.description,
                                          requiresOrigin: true, origin: presenter.planning.origin,
                                          setOrigin: { place in
                                              presenter.cancelRecommendations()
                                              presenter.planning.origin = place.location
                                              presenter.planning.originLabel = place.name
                                              presenter.planning.draftChanged()
                                          },
                                          load: { await presenter.loadRecommendationsIfNeeded() },
                                          refresh: { _ = await presenter.suggest() }, cancel: presenter.cancelRecommendations,
                                          toggle: presenter.toggle,
                                          findPlace: { presenter.push(.places) }, complete: presenter.finishChoosingPlaces)
            case .mainSpot:
                MainSpotQuestionView(places: presenter.selected, selection: presenter.mainSpot,
                                     select: { presenter.mainSpot = $0; presenter.stay = nil },
                                     next: { run { await presenter.finishMainSpot() } },
                                     skip: {
                                         presenter.mainSpot = .automatic; presenter.stay = nil
                                         run { await presenter.finishSurvey() }
                                     }, researchesWithLuna: presenter.planning.supportsOnDevicePlanning,
                                     usesV41: presenter.usesV41,
                                     scheduleSummary: presenter.usesV41 ? presenter.scheduleSummary : nil,
                                     editSchedule: presenter.usesV41 ? { openScheduleOptions() } : nil)
            case .stay:
                StayDurationQuestionView(placeName: presenter.selected.first(where: { $0.id == presenter.mainSpot.placeID })?.place.name ?? "your main spot",
                                         selection: presenter.stay,
                                         select: { value in presenter.stay = value; run { await presenter.finishSurvey() } },
                                         skip: { presenter.stay = nil; run { await presenter.finishSurvey() } })
            case .review:
                if let proposal = presenter.reviewProposal {
                    ItineraryReviewView(presenter: presenter.planning, initialProposal: proposal)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { planningErrorBanner(for: route) }
        .disabled(presenter.isProcessing)
        .toolbar(presenter.isProcessing ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if route == .mainSpot && presenter.planning.supportsOnDevicePlanning {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schedule", systemImage: "calendar") { openScheduleOptions() }
                        .accessibilityIdentifier("tripScheduleOptions")
                }
            }
            if presenter.path.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    cancelButton
                }
            }
        }
    }

    @ViewBuilder private func planningErrorBanner(for route: TripCreationRoute) -> some View {
        if presenter.route == route, [.mainSpot, .stay, .availability].contains(route),
           let error = presenter.error, !presenter.isProcessing {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote)
                if let assessment = presenter.scheduleAssessment, let input = presenter.planning.firstItineraryJob?.input {
                    ForEach(Array(assessment.messages(in: input).prefix(4)), id: \.self) { Text($0).font(.footnote) }
                    ForEach(assessment.durationAlternatives) { alternative in
                        let name = presenter.selected.first { $0.id == alternative.placeID }?.place.name ?? "Visit"
                        Text(alternative.source == "luna_experience_estimate" ? "Alternative based on Luna's estimated duration range." : "Alternative within your accepted duration range.")
                            .font(.footnote)
                        Button("Use \(alternative.proposedSeconds / 60) min at \(name) instead of \(alternative.originalSeconds / 60) min") {
                            run { await presenter.acceptDurationAlternative(alternative) }
                        }
                        .accessibilityIdentifier("acceptShorterVisit")
                    }
                    if !assessment.regularConflicts.isEmpty || assessment.conflicts.contains(where: { $0.placeID != nil }) || assessment.stopReason == "date_conflict" {
                        Button("Review visit availability") { presenter.reviewVisitAvailability() }
                    }
                }
                if presenter.canTryTomorrow {
                    Button("Try tomorrow") { run { await presenter.tryTomorrow() } }
                }
                if let code = presenter.planning.firstItineraryJob?.errorCode,
                   ["V4_NO_SCHEDULE", "V4_DURATION_UNKNOWN", "V4_WINDOW_TOO_SHORT", "V4_TODAY_TOO_SHORT",
                    "V4_TOMORROW_TOO_SHORT", "V4_TOMORROW_UNVERIFIED", "V41_NO_SCHEDULE", "V41_ACCESS_CONFLICT",
                    "V41_DATE_CONFLICT", "V41_BUDGET_REACHED"].contains(code) {
                    Button("Adjust schedule") { openScheduleOptions() }
                }
                if presenter.planning.origin == nil, presenter.planningHandoffMessage == nil {
                    Button("Choose starting point") { showsStartingPointSearch = true }
                } else if presenter.needsPocketSettings, let openPocketSettings {
                    Button("Open Pocket settings", action: openPocketSettings)
                } else if route != .availability, presenter.planningHandoffMessage == nil {
                    Button(presenter.checksExistingRequest ? "Check status" : "Try again") { run { await presenter.plan() } }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface)
            .accessibilityIdentifier("tripPlanningError")
        }
    }

    private func openScheduleOptions() {
        presenter.prepareScheduleOptions()
        showsScheduleOptions = true
    }

    private var cancelButton: some View {
        Button("Cancel", systemImage: "xmark", action: dismiss)
            .labelStyle(.iconOnly)
            .disabled(presenter.isProcessing || presenter.planning.isBusy)
            .accessibilityIdentifier("tripCreationCancel")
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !presenter.isProcessing, !isRunningOperation else { return }
        isRunningOperation = true
        operation = Task {
            defer { isRunningOperation = false }
            await action()
        }
    }
}
