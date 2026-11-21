import SwiftUI
import C67Domain

struct TripCreationView: View {
    private enum ScheduleOptions: Hashable, Identifiable {
        case all, field(ScheduleField)
        var id: Self { self }
        var target: ScheduleField? {
            if case .field(let target) = self { return target }
            return nil
        }
    }

    @Environment(\.openURL) private var openPrivacyURL
    @Environment(\.locale) private var locale
    @State private var presenter: TripCreationPresenter
    let dismiss: () -> Void
    let openPocketSettings: (() -> Void)?
    @State private var isRunningOperation = false
    @State private var operation: Task<Void, Never>?
    @State private var showsStartingPointSearch = false
    @State private var scheduleOptions: ScheduleOptions?
    @State private var showsScheduleDetails = false
    @State private var pendingScheduleTarget: ScheduleField?
    @State private var showsMyPlaces = false

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
                TripProcessingView(advances: false, messageOverride: presenter.planning.progress,
                                   activity: presenter.planning.activity)
                if presenter.planning.canCancelPlanning {
                    Button("Cancel planning", role: .destructive) {
                        operation?.cancel()
                        Task { _ = await presenter.planning.cancelPlanning() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 78)
                }
                Button { operation?.cancel(); dismiss() } label: {
                    Text(presenter.planning.supportsOnDevicePlanning ? "Continue later" : "Cancel")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(20)
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
        .confirmationDialog("Use AI to help plan this trip?", isPresented: $presenter.requestsAIConsent, titleVisibility: .visible) {
            Button("Allow AI assistance for this trip") { run { await presenter.chooseExternalAI(true) } }
            Button("Enter durations myself") { run { await presenter.chooseExternalAI(false) } }
            if let policy = TravelantsPrivacy.policyURL {
                Button("Privacy Policy") { openPrivacyURL(policy) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let recipient = TravelantsPrivacy.aiRecipient {
                Text("Travelants sends selected places and pins, your starting and ending points, trip dates, time zone and preferences to Pocket. Pocket shares selected place details, dates, preferences and weather context with \(recipient) to suggest activities and visit durations.")
            }
        }
        .onChange(of: presenter.manualDurationTarget) { _, id in
            if let id {
                presenter.manualDurationTarget = nil
                presenter.prepareScheduleOptions()
                scheduleOptions = .field(.duration(id))
            }
        }
        .sheet(item: $scheduleOptions) { options in
            PocketScheduleOptionsSheet(presenter: presenter, target: options.target)
        }
        .sheet(isPresented: $showsMyPlaces) {
            PlacesSelectionSheet(places: presenter.selected, remove: presenter.toggle)
        }
        .sheet(isPresented: $showsScheduleDetails, onDismiss: {
            if let target = pendingScheduleTarget {
                pendingScheduleTarget = nil
                scheduleOptions = .field(target)
            }
        }) {
            NavigationStack {
                List {
                    if let assessment = presenter.scheduleAssessment, let input = presenter.planning.firstItineraryJob?.input {
                        if !assessment.conflicts.isEmpty || !assessment.regularConflicts.isEmpty {
                            Section("Conflicts") {
                                ForEach(Array((assessment.conflicts + assessment.regularConflicts).enumerated()), id: \.offset) { _, issue in
                                    scheduleIssueRow(issue, input: input)
                                }
                            }
                        }
                        if !assessment.unresolved.isEmpty {
                            Section("Information to check") {
                                ForEach(Array(assessment.unresolved.enumerated()), id: \.offset) { _, issue in scheduleIssueRow(issue, input: input) }
                            }
                        }
                        if !assessment.dates.isEmpty {
                            Section("Dates checked") {
                                ForEach(Array(assessment.dates.enumerated()), id: \.offset) { _, day in
                                    VStack(alignment: .leading) {
                                        Text(ItineraryFormatting.date(day.date, zone: input.timeZone, locale: locale))
                                        Text(dateStatus(day))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if !presenter.automaticallySchedules, !assessment.durationAlternatives.isEmpty {
                            Section("Duration alternatives") {
                                ForEach(assessment.durationAlternatives) { alternative in
                                    let name = presenter.selected.first { $0.id == alternative.placeID }?.place.name ?? "Visit"
                                    Button("Use \(alternative.proposedSeconds / 60) min at \(name) instead of \(alternative.originalSeconds / 60) min") {
                                        showsScheduleDetails = false
                                        run { await presenter.acceptDurationAlternative(alternative) }
                                    }
                                    .accessibilityIdentifier("acceptShorterVisit")
                                }
                            }
                        }
                        if !presenter.automaticallySchedules,
                           (assessment.conflicts + assessment.regularConflicts + assessment.unresolved).contains(where: { $0.placeID != nil }) {
                            Section {
                                Button("Review visit availability") {
                                    showsScheduleDetails = false
                                    presenter.reviewVisitAvailability()
                                }
                            }
                        }
                    }
                }
                .environment(\.timeZone, TimeZone(identifier: presenter.planning.timeZone) ?? .current)
                .navigationTitle("Schedule details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsScheduleDetails = false } } }
            }
        }
        .fullScreenCover(isPresented: $showsStartingPointSearch) {
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
                              isSearching: presenter.isSearching, hasSearched: presenter.hasSearchedCurrentQuery,
                              showsPreviousResults: presenter.showsPreviousResults, error: presenter.searchError,
                              synthetic: presenter.mode.hasPrefix("Mock"), maximumSelection: TripCreationPresenter.maximumPlaces,
                              origin: presenter.planning.origin, search: { await presenter.search() }, toggle: presenter.toggle) {
                    if presenter.path.contains(.recommendations) { presenter.path.removeLast() }
                    else { presenter.finishChoosingPlaces() }
                }
            case .availability:
                PocketVisitAvailabilityView(presenter: presenter) { run { await presenter.plan() } }
            case .recommendations:
                PlacesRecommendationsView(batch: presenter.batch, selected: presenter.selected,
                                          isLoading: presenter.isSuggesting, error: presenter.recommendationError,
                                          requiresOrigin: true, origin: presenter.planning.origin,
                                          setOrigin: { place in
                                              presenter.cancelRecommendations()
                                              presenter.planning.origin = place.location
                                              presenter.planning.originLabel = place.name
                                              presenter.planning.draftChanged()
                                          },
                                          maximumSelection: TripCreationPresenter.maximumPlaces,
                                          minimumSelection: 3, countsInNextButton: true,
                                          load: { await presenter.loadRecommendationsIfNeeded() },
                                          refresh: { _ = await presenter.suggest() }, cancel: presenter.cancelRecommendations,
                                          toggle: presenter.toggle,
                                          findPlace: { presenter.push(.places) }, complete: presenter.finishChoosingPlaces)
            case .mainSpot:
                MainSpotQuestionView(places: presenter.selected, selection: presenter.mainSpot,
                                     select: presenter.selectMainSpot,
                                     next: { run { await presenter.finishMainSpot() } },
                                     showsNext: presenter.error == nil || presenter.connectionNotice == nil,
                                     researchesWithLuna: presenter.planning.supportsOnDevicePlanning,
                                     usesV41: presenter.usesV41,
                                     usesFoundationModels: presenter.usesFoundationModels,
                                     scheduleSummary: showsManualScheduleControl ? presenter.scheduleSummary : nil,
                                     editSchedule: showsManualScheduleControl ? { openScheduleOptions() } : nil)
            case .stay:
                StayDurationQuestionView(placeName: presenter.selected.first(where: { $0.id == presenter.mainSpot.placeID })?.place.name ?? "your main spot",
                                         selection: presenter.stay,
                                         select: { value in presenter.stay = value; run { await presenter.finishSurvey() } },
                                         skip: { presenter.stay = nil; run { await presenter.finishSurvey() } })
            case .review:
                if let proposal = presenter.reviewProposal {
                    ItineraryReviewView(presenter: presenter.planning, initialProposal: proposal)
                        .onAppear { presenter.recordReviewAppearance() }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { planningErrorBanner(for: route) }
        .disabled(presenter.isProcessing)
        .toolbar(presenter.isProcessing ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
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
            Group {
                if let notice = presenter.connectionNotice {
                    connectionBanner(notice)
                } else {
                    let code = presenter.planning.firstItineraryJob?.errorCode
                    RecoveryNotice(title: presenter.checksExistingRequest ? "Request status" : "Itinerary needs attention",
                                   message: planningMessage(error, code: code), primary: planningAction(code: code, route: route),
                                   secondary: secondaryPlanningAction)
                }
            }
            .accessibilityIdentifier("tripPlanningError")
        }
    }

    private func connectionBanner(_ notice: TripCreationPresenter.ConnectionNotice) -> RecoveryNotice {
        let checking = presenter.checksExistingRequest
        let action = RecoveryNotice.Action(title: checking ? "Check status" : "Try again") {
            run { await presenter.plan() }
        }
        switch notice {
        case .takingLonger:
            return RecoveryNotice(title: "Your itinerary is taking longer than expected",
                                  message: "Check for a result using the same request. Your selections are kept.",
                                  icon: "clock", primary: action)
        case .loadFailed:
            return RecoveryNotice(title: "Couldn’t load your itinerary",
                                  message: checking
                                      ? "Your selections are kept. Check the same request when you’re connected."
                                      : "Your selections are kept. Try again when you’re ready.",
                                  primary: action)
        }
    }

    private var secondaryPlanningAction: RecoveryNotice.Action? {
        if presenter.scheduleAssessment != nil {
            return .init(title: "View schedule details") { pendingScheduleTarget = nil; showsScheduleDetails = true }
        }
        if !presenter.automaticallySchedules, presenter.canTryTomorrow {
            return .init(title: "Adjust schedule") { openScheduleOptions() }
        }
        return nil
    }

    private func planningMessage(_ message: String, code: String?) -> String {
        switch code {
        case "V4_DURATION_UNKNOWN": "A visit duration is unavailable. Add it to continue."
        case "V41_ACCESS_CONFLICT": "A visit conflicts with available hours or an activity session."
        case "V41_DATE_CONFLICT": "A confirmed visit falls outside the trip date."
        case "V41_BUDGET_REACHED": "Route checking stopped before a complete schedule could be verified."
        case "V41_NO_SCHEDULE": "No complete schedule was verified among the routes checked."
        default: message
        }
    }

    private func planningAction(code: String?, route: TripCreationRoute) -> RecoveryNotice.Action? {
        if presenter.planningHandoffMessage != nil {
            return .init(title: "Review My Places") { showsMyPlaces = true }
        }
        if presenter.planning.origin == nil {
            return .init(title: "Choose starting point") { showsStartingPointSearch = true }
        }
        if presenter.needsPocketSettings || presenter.planning.creationIssue?.recovery == .signIn, let openPocketSettings {
            return .init(title: "Open Account", perform: openPocketSettings)
        }
        if presenter.checksExistingRequest {
            return .init(title: "Check status") { run { await presenter.plan() } }
        }
        if !presenter.automaticallySchedules, presenter.canTryTomorrow {
            return .init(title: "Try tomorrow") { run { await presenter.tryTomorrow() } }
        }
        switch code {
        case "FOUNDATION_MODELS_UNAVAILABLE", "FOUNDATION_MODELS_GENERATION_FAILED",
             "V4_DURATION_UNKNOWN", "V4_NO_SCHEDULE", "V4_WINDOW_TOO_SHORT", "V4_TODAY_TOO_SHORT",
             "V4_TOMORROW_TOO_SHORT", "V4_TOMORROW_UNVERIFIED", "V41_NO_SCHEDULE", "V41_ACCESS_CONFLICT", "V41_DATE_CONFLICT":
            if !presenter.automaticallySchedules {
                return .init(title: "Adjust schedule") { openScheduleOptions() }
            }
            return nil
        default:
            guard route != .availability else { return nil }
            let title: LocalizedStringKey = presenter.planning.creationIssue?.recovery == .wait ? "Try again later" : "Try again"
            return .init(title: title) { run { await presenter.plan() } }
        }
    }

    private func dateStatus(_ day: PlanningDateAssessment) -> LocalizedStringKey {
        if day.completeCandidates > 0 { return "Schedule found" }
        if day.stopReason == "provider_unverified" { return "Could not check this date" }
        if day.stopReason == "date_conflict" { return "Conflicting visit date" }
        if day.stopReason == "preflight_conflict" {
            if presenter.planning.firstItineraryJob?.errorCode == "V4_DURATION_UNKNOWN" { return "Visit duration needed" }
            return "Stopped before checking routes"
        }
        if day.stopReason.hasSuffix("_budget_exhausted") { return "Route checking reached its limit" }
        return "No complete schedule verified"
    }

    @ViewBuilder private func scheduleIssueRow(_ issue: PlanningScheduleIssue, input: PlanningInput) -> some View {
        let target: ScheduleField? = switch issue.code {
        case "duration_unknown", "duration_exceeds_all_windows": issue.placeID.map(ScheduleField.duration)
        case "session_arrival_missed": issue.placeID.map(ScheduleField.checkIn)
        case "session_outside_date", "required_visits_overlap", "required_target_missed", "hard_target_missed",
             "target_outside_availability": issue.placeID.map(ScheduleField.session)
        case "all_day_closed", "date_access_unverified": issue.placeID.map(ScheduleField.access)
        case "visit_outside_hours_or_entry": issue.placeID.map(ScheduleField.entry)
        case "return_deadline_exceeded", "duration_exceeds_day": .finish
        case "waiting_permission_unknown": .waiting
        default: nil
        }
        if !presenter.automaticallySchedules, let target {
            Button {
                presenter.prepareScheduleOptions()
                pendingScheduleTarget = target
                showsScheduleDetails = false
            } label: {
                HStack {
                    Text(issue.message(in: input))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
            .accessibilityHint("Opens the related schedule field")
        } else {
            Text(issue.message(in: input))
        }
    }

    private var showsManualScheduleControl: Bool {
        presenter.planning.supportsOnDevicePlanning && !presenter.automaticallySchedules
    }

    private func openScheduleOptions() {
        presenter.prepareScheduleOptions()
        scheduleOptions = .all
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
