import SwiftUI
import C67Domain

struct ItineraryReviewView: View {
    let presenter: PlanningPresenter
    let initialProposal: PlanProposal
    @State private var showsSaveName = false
    @State private var saveName = ""
    @State private var tripName: String?
    @State private var showsEditName = false
    @State private var nameDraft = ""
    @State private var startsAfterSave = false
    @State private var lastReviewedProposal: PlanProposal?
    @State private var editRoute: ItineraryEditRoute?
    @State private var orderChanged = false

    private var proposal: PlanProposal { presenter.job?.result?.proposal ?? lastReviewedProposal ?? initialProposal }
    private var displayedName: String { tripName ?? proposal.input.title }
    private var canStartToday: Bool {
        guard proposal.usesExperienceFlow else { return false }
        guard proposal.input.enginePreferences?.orderingMethod?.isSchedule == true else { return true }
        return PlanningDayWindow.isSameDay(proposal.departureAt ?? proposal.input.startsAt, .now, timeZone: proposal.input.timeZone)
    }
    private var canEditName: Bool {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 120
    }
    private var retryAction: (() -> Void)? {
        if presenter.needsFreshProposal || presenter.reviewIssue?.recovery == .regenerate { return { regenerate() } }
        guard let issue = presenter.reviewIssue, let recovery = issue.recovery, recovery != .signIn else { return nil }
        return { Task { await presenter.retryReviewIssue() } }
    }

    private var retryTitle: LocalizedStringKey {
        if presenter.needsFreshProposal || presenter.reviewIssue?.recovery == .regenerate { return "Request a fresh plan" }
        if presenter.reviewIssue?.recovery == .checkStatus { return "Check status" }
        switch presenter.reviewIssue?.operation {
        case .changeRoute: return "Retry route update"
        case .save: return "Retry saving"
        default: return "Try again"
        }
    }

    var body: some View {
        ItineraryListView(proposal: proposal, excludedPlaces: initialProposal.unscheduledPlaces ?? [],
                          editEndpoints: initialProposal.input.enginePreferences?.automaticFirstPlan == true ? { editRoute = $0 } : nil,
                          isSaving: presenter.isBusy, error: presenter.reviewIssue?.message,
                          retryTitle: retryTitle,
                          canSave: !presenter.needsFreshProposal && presenter.job?.result?.proposal != nil && presenter.draftInput == proposal.input,
                          heading: !proposal.usesExperienceFlow ? nil : displayedName,
                          editTitle: !proposal.usesExperienceFlow ? nil : { nameDraft = displayedName; showsEditName = true },
                          editDeparture: !proposal.usesExperienceFlow ? nil : { editRoute = .estimatedDeparture },
                          startNow: canStartToday ? { saveName = displayedName; startsAfterSave = true; save() } : nil,
                          actionTitle: !proposal.usesExperienceFlow ? "Save Itinerary" : "Save your trip for later…",
                          retry: retryAction,
                          refreshRoute: proposal.hasExperienceTravelFallback ? { refreshRoute() } : nil,
                          lookupHours: { await presenter.openingHours(placeID: $0) },
                          edit: edit,
                          save: { saveName = displayedName; startsAfterSave = false; showsSaveName = true },
                          move: !presenter.needsFreshProposal && presenter.draftInput == proposal.input ? move : nil)
            .modifier(ItinerarySaveNameDialog(isPresented: $showsSaveName, name: $saveName, originalName: proposal.input.title, regeneratesOnRename: !proposal.usesExperienceFlow, save: save))
            .alert("Edit trip name", isPresented: $showsEditName) {
                TextField("Itinerary name", text: $nameDraft)
                Button("Done") { tripName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .disabled(!canEditName)
                Button("Cancel", role: .cancel) { }
            } message: {
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { Text("Enter a trip name.") }
                else if name.count > 120 { Text("Shorten the trip name to 120 characters or fewer.") }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if orderChanged || proposal.input.title != initialProposal.input.title {
                    Text("Updated itinerary. Review it before saving.")
                        .font(.footnote).padding().frame(maxWidth: .infinity).background(AppColor.surface)
                }
            }
            .disabled(presenter.isBusy)
            .task {
                if proposal.usesExperienceFlow, proposal.experienceRouteCheckedAt == nil {
                    await presenter.updateExperienceRoute()
                }
            }
            .onChange(of: presenter.job?.result?.proposal, initial: true) { _, current in
                if let current { lastReviewedProposal = current }
            }
            .overlay {
                if presenter.isBusy {
                    ProgressView(presenter.progress ?? String(localized: "Working on your itinerary…"))
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .fullScreenCover(item: $editRoute.only(\.picksPlace)) { route in
                switch route {
                case .addPlace:
                    PlanningSearchSheet(near: presenter.origin, title: "Add a place", select: add)
                case .startingPoint:
                    PlanningSearchSheet(near: presenter.origin, title: "Starting point") { place in
                        presenter.origin = place.location
                        presenter.originLabel = place.name
                        regenerate()
                    }
                case .endPoint:
                    PlanningSearchSheet(near: presenter.origin, title: "End point") { place in
                        presenter.enginePreferences?.endPoint = place.location
                        presenter.enginePreferences?.endPointName = place.name
                        regenerate()
                    }
                case .visit, .tripTime, .estimatedDeparture:
                    EmptyView()
                }
            }
            .sheet(item: $editRoute.only { !$0.picksPlace }) { route in
                switch route {
                case .visit(let place):
                    ItineraryVisitEditor(place: place, zone: proposal.input.timeZone,
                                         startsAt: proposal.input.startsAt, orderingOnly: proposal.usesExperienceFlow, update: update)
                case .addPlace, .startingPoint, .endPoint:
                    EmptyView()
                case .estimatedDeparture:
                    if let departure = proposal.estimatedExperienceDeparture {
                        ExperienceDepartureEditor(departure: departure, timeZone: proposal.input.timeZone, update: updateDeparture)
                    }
                case .tripTime:
                    ItineraryTripTimeEditor(input: proposal.input) { start, end in
                        presenter.startsAt = start
                        presenter.finishBy = end
                        regenerate()
                    }
                }
            }
    }

    private func edit(_ id: UUID?) {
        if let id, var place = presenter.places.first(where: { $0.id == id }) {
            if proposal.usesExperienceFlow, place.durationOverridden != true,
               let stop = proposal.stopsWithExperienceEstimates.first(where: { $0.id == id }) { place.visitSeconds = stop.visitSeconds }
            editRoute = .visit(place)
        } else if id == nil {
            editRoute = .addPlace
        }
    }

    private func update(_ original: PlanningPlace) {
        var place = original
        if proposal.usesExperienceFlow { place.durationOverridden = true }
        guard let index = presenter.places.firstIndex(where: { $0.id == place.id }), !presenter.isBusy else { return }
        presenter.places[index] = place
        regenerate()
    }

    private func add(_ place: PlanningPlace) {
        guard proposal.usesExperienceFlow || presenter.places.count < 6, !presenter.isBusy else { return }
        presenter.places.append(place)
        regenerate()
    }

    private func move(_ source: UUID, _ destination: UUID) async {
        guard !presenter.isBusy, !presenter.needsFreshProposal,
              presenter.draftInput == proposal.input,
              let sourceIndex = proposal.stops.firstIndex(where: { $0.id == source }),
              let targetIndex = proposal.stops.firstIndex(where: { $0.id == destination }) else { return }
        var ordered = proposal.stops.map(\.id)
        ordered.insert(ordered.remove(at: sourceIndex), at: targetIndex)
        if proposal.usesExperienceFlow {
            await presenter.updateExperienceRoute(orderedIDs: ordered)
            if presenter.reviewIssue == nil { orderChanged = true }
            return
        }
        let places = Dictionary(uniqueKeysWithValues: presenter.places.map { ($0.id, $0) })
        let reordered = ordered.compactMap { places[$0] }
        guard reordered.count == presenter.places.count else { return }
        await presenter.updateTimedReviewOrder(reordered)
        if presenter.reviewIssue == nil { orderChanged = true }
    }

    private func regenerate() {
        let previousDeparture = !proposal.usesExperienceFlow ? nil : proposal.departureAt
        presenter.draftChanged()
        Task {
            await presenter.request(reviewing: true)
            if let previousDeparture, presenter.reviewIssue == nil, let updated = presenter.job?.result?.proposal,
               let zone = TimeZone(identifier: updated.input.timeZone) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                if calendar.isDate(previousDeparture, inSameDayAs: updated.input.startsAt) {
                    await presenter.setExperienceDeparture(previousDeparture)
                }
            }
        }
    }

    private func updateDeparture(_ departure: Date) {
        Task {
            await presenter.setExperienceDeparture(departure)
        }
    }

    private func save() {
        let name = saveName.isEmpty ? displayedName : saveName
        let startsTrip = startsAfterSave
        Task {
            await presenter.saveReviewedProposal(named: name, startImmediately: startsTrip)
        }
    }

    private func refreshRoute() {
        Task {
            await presenter.updateExperienceRoute()
        }
    }
}

private struct ExperienceDepartureEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var departure: Date
    let timeZone: String
    let update: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $departure, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                DatePicker("Time", selection: $departure, displayedComponents: .hourAndMinute)
                Text("Changing departure recalculates driving estimates. Weather and daylight information may not cover the new date.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .environment(\.timeZone, TimeZone(identifier: timeZone) ?? .current)
            .navigationTitle("Edit departure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { update(departure); dismiss() }
                }
            }
        }
    }
}

private struct ItineraryTripTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var departure: Date
    @State private var finishBy: Date
    let zone: TimeZone
    let update: (Date, Date) -> Void

    init(input: PlanningInput, update: @escaping (Date, Date) -> Void) {
        _departure = State(initialValue: input.startsAt)
        _finishBy = State(initialValue: input.finishBy)
        zone = TimeZone(identifier: input.timeZone) ?? .current
        self.update = update
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Depart", selection: $departure, in: PartialRangeFrom(Date()))
                DatePicker("Finish by", selection: $finishBy, displayedComponents: .hourAndMinute)
                Text("Changing the date can change opening hours and invalidate personal confirmations.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .environment(\.calendar, calendar)
            .environment(\.timeZone, zone)
            .navigationTitle("Trip timing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update itinerary") {
                        update(departure, finishBy)
                        dismiss()
                    }.disabled(finishBy <= departure || !calendar.isDate(departure, inSameDayAs: finishBy))
                }
            }
            .onChange(of: departure) { previous, newValue in
                guard !calendar.isDate(previous, inSameDayAs: newValue) else { return }
                let time = calendar.dateComponents([.hour, .minute], from: finishBy)
                finishBy = calendar.startOfDay(for: newValue)
                    .addingTimeInterval(Double((time.hour ?? 20) * 3600 + (time.minute ?? 0) * 60))
            }
        }
    }
}
