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
    @State private var pendingDeparture: Date?
    @State private var pendingRouteOrder: [UUID]?
    @State private var editRoute: ItineraryEditRoute?
    @State private var orderChanged = false

    private var proposal: PlanProposal { presenter.job?.result?.proposal ?? initialProposal }
    private var displayedName: String { tripName ?? proposal.input.title }
    private var canEditName: Bool {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 120
    }
    private var retryAction: (() -> Void)? {
        if presenter.needsFreshProposal || presenter.job?.result?.proposal == nil { return { regenerate() } }
        if presenter.error != nil {
            if let pendingDeparture { return { updateDeparture(pendingDeparture) } }
            if let pendingRouteOrder { return { updateStopOrder(pendingRouteOrder) } }
            return { save() }
        }
        return nil
    }

    var body: some View {
        ItineraryListView(proposal: proposal, excludedPlaces: initialProposal.unscheduledPlaces ?? [],
                          editEndpoints: initialProposal.input.enginePreferences?.automaticFirstPlan == true ? { editRoute = $0 } : nil,
                          isSaving: presenter.isBusy, error: presenter.error,
                          canSave: !presenter.needsFreshProposal && presenter.job?.result?.proposal != nil && presenter.draftInput == proposal.input,
                          heading: proposal.experiencePlan == nil ? nil : displayedName,
                          editTitle: proposal.experiencePlan == nil ? nil : { nameDraft = displayedName; showsEditName = true },
                          editDeparture: proposal.experiencePlan == nil ? nil : { editRoute = .estimatedDeparture },
                          startNow: proposal.experiencePlan == nil ? nil : { saveName = displayedName; startsAfterSave = true; save() },
                          actionTitle: proposal.experiencePlan == nil ? "Save Itinerary" : "Save your trip for later…",
                          retry: retryAction,
                          refreshRoute: proposal.hasExperienceTravelFallback ? { Task { await presenter.updateExperienceRoute() } } : nil,
                          edit: edit,
                          save: { saveName = displayedName; startsAfterSave = false; showsSaveName = true }, move: move)
            .modifier(ItinerarySaveNameDialog(isPresented: $showsSaveName, name: $saveName, originalName: proposal.input.title, regeneratesOnRename: proposal.experiencePlan == nil, save: save))
            .alert("Edit trip name", isPresented: $showsEditName) {
                TextField("Itinerary name", text: $nameDraft)
                Button("Done") { tripName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .disabled(!canEditName)
                Button("Cancel", role: .cancel) { }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if orderChanged || proposal.input.title != initialProposal.input.title {
                    Text("Updated itinerary. Review it before saving.")
                        .font(.footnote).padding().frame(maxWidth: .infinity).background(AppColor.surface)
                }
            }
            .disabled(presenter.isBusy)
            .task {
                if proposal.experiencePlan != nil, proposal.experienceRouteCheckedAt == nil {
                    await presenter.updateExperienceRoute()
                }
            }
            .overlay {
                if presenter.isBusy {
                    ProgressView(presenter.progress ?? String(localized: "Working on your itinerary…"))
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .sheet(item: $editRoute) { route in
                switch route {
                case .visit(let place):
                    ItineraryVisitEditor(place: place, zone: proposal.input.timeZone,
                                         startsAt: proposal.input.startsAt, orderingOnly: proposal.experiencePlan != nil, update: update)
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
            if proposal.experiencePlan != nil, place.durationOverridden != true,
               let stop = proposal.stopsWithExperienceEstimates.first(where: { $0.id == id }) { place.visitSeconds = stop.visitSeconds }
            editRoute = .visit(place)
        } else if id == nil {
            editRoute = .addPlace
        }
    }

    private func update(_ original: PlanningPlace) {
        var place = original
        if proposal.experiencePlan != nil { place.durationOverridden = true }
        guard let index = presenter.places.firstIndex(where: { $0.id == place.id }), !presenter.isBusy else { return }
        presenter.places[index] = place
        regenerate()
    }

    private func add(_ place: PlanningPlace) {
        guard proposal.experiencePlan != nil || presenter.places.count < 6, !presenter.isBusy else { return }
        presenter.places.append(place)
        regenerate()
    }

    private func move(_ source: UUID, _ destination: UUID) {
        guard !presenter.isBusy, !presenter.needsFreshProposal,
              presenter.draftInput == proposal.input,
              let sourceIndex = proposal.stops.firstIndex(where: { $0.id == source }),
              let targetIndex = proposal.stops.firstIndex(where: { $0.id == destination }) else { return }
        var ordered = proposal.stops.map(\.id)
        ordered.insert(ordered.remove(at: sourceIndex), at: targetIndex)
        if proposal.experiencePlan != nil {
            updateStopOrder(ordered)
            return
        }
        let places = Dictionary(uniqueKeysWithValues: presenter.places.map { ($0.id, $0) })
        let reordered = ordered.compactMap { places[$0] }
        guard reordered.count == presenter.places.count else { return }
        presenter.places = reordered
        presenter.preservesPlaceOrder = true
        orderChanged = true
        regenerate()
    }

    private func updateStopOrder(_ ids: [UUID]) {
        pendingRouteOrder = ids
        Task {
            await presenter.updateExperienceRoute(orderedIDs: ids)
            if presenter.error == nil {
                pendingRouteOrder = nil
                orderChanged = true
            }
        }
    }

    private func regenerate() {
        let previousDeparture = proposal.experiencePlan == nil ? nil : proposal.departureAt
        presenter.draftChanged()
        Task {
            await presenter.request()
            if let previousDeparture, presenter.error == nil, let updated = presenter.job?.result?.proposal,
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
        pendingDeparture = departure
        Task {
            await presenter.setExperienceDeparture(departure)
            if presenter.error == nil { pendingDeparture = nil }
        }
    }

    private func save() {
        let name = saveName.isEmpty ? displayedName : saveName
        let startsTrip = startsAfterSave
        Task { await presenter.saveReviewedProposal(named: name, startImmediately: startsTrip) }
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
