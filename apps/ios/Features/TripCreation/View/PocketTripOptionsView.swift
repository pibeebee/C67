import SwiftUI
import C67Domain

struct PocketTripOptionsView: View {
    @Bindable var presenter: TripCreationPresenter
    var body: some View {
        @Bindable var planning = presenter.planning
        if let options = Binding($planning.enginePreferences) {
            PocketTripOptionFields(options: options, places: presenter.selected.map(\.place), labels: planning.preferenceLabels)
                .onChange(of: planning.enginePreferences) { _, _ in planning.draftChanged() }
        }
    }
}

private struct PocketTripOptionFields: View {
    @Binding var options: PlanningPreferences
    let places: [PlanningPlace]
    let labels: [PlanningPreferenceLabel]
    var body: some View {
        Section("Schedule constraints") {
            Toggle("Depart any time within the window", isOn: $options.flexibleDeparture)
            Toggle("Return to the starting point by finish time", isOn: $options.returnToOrigin)
            Stepper("Allowed waiting: \(options.maximumWaitMinutes) min", value: $options.maximumWaitMinutes, in: 0 ... 120, step: 5)
            Toggle("Avoid rain during outdoor visits", isOn: $options.avoidRain)
            Picker("Last destination", selection: $options.lastPlaceID) {
                Text("No fixed last destination").tag(UUID?.none)
                ForEach(places) { place in Text(place.name).tag(Optional(place.id)) }
            }
        }
        if labels.contains(where: { $0.allowsCondition && options.labels.contains($0.id) }) {
            Section("Activity conditions") {
                ForEach(labels.filter { $0.allowsCondition && options.labels.contains($0.id) }) { label in
                    Picker(label.title, selection: Binding(get: { options.conditions[label.id] ?? .liked }, set: { options.conditions[label.id] = $0 })) {
                        Text("Preferred").tag(PlanningCondition.liked)
                        Text("Required").tag(PlanningCondition.required)
                        Text("Avoid").tag(PlanningCondition.avoided)
                        Text("No condition").tag(PlanningCondition.neutral)
                    }
                }
                Text("Required conditions need current evidence. Unknown values do not count as a match.").font(.footnote)
            }
        }
        Section("Visit research") {
            if options.orderingMethod == .hybridV42FoundationModels {
                Text("Foundation Models estimates activities and durations on your device. Apple provides travel estimates, and Pocket can look up regular hours.").font(.footnote)
            } else {
                Text("Travelants researches the selected place names, pins, available branch details and preferences using the Pocket server and Luna. Opening hours and entry rules require retrieved sources; suggested durations remain estimates. Apple provides driving times.").font(.footnote)
            }
        }
    }
}

/// Trip constraints available before the first scheduler request.
enum ScheduleField: Hashable {
    case finish, waiting, place(UUID), duration(UUID), access(UUID), entry(UUID), session(UUID), checkIn(UUID)

    var placeID: UUID? {
        switch self {
        case .place(let id), .duration(let id), .access(let id), .entry(let id), .session(let id), .checkIn(let id): id
        case .finish, .waiting: nil
        }
    }
}

struct PocketScheduleOptionsSheet: View {
    @Bindable var presenter: TripCreationPresenter
    var target: ScheduleField?
    @State private var choosesEndpoint = false
    @State private var revealedField: ScheduleField?
    @AccessibilityFocusState private var focusedField: ScheduleField?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    private var zone: TimeZone { TimeZone(identifier: presenter.planning.timeZone) ?? .current }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private var firstInvalidField: ScheduleField? {
        let planning = presenter.planning
        guard planning.finishBy > planning.startsAt,
              calendar.isDate(planning.startsAt, inSameDayAs: planning.finishBy) else { return .finish }
        for item in presenter.selected {
            if let access = item.place.visitConfirmation {
                if access.opensAt >= access.closesAt { return .access(item.id) }
                if let cutoff = access.lastEntryAt, cutoff < access.opensAt || cutoff > access.closesAt { return .entry(item.id) }
            }
            if let session = item.place.activitySession {
                if session.startsAt >= session.endsAt { return .session(item.id) }
                if let cutoff = session.arriveBy, cutoff > session.startsAt { return .checkIn(item.id) }
            }
        }
        return nil
    }

    private var focusedVisit: RecommendedPlace? {
        guard let placeID = (revealedField ?? target)?.placeID else { return nil }
        return presenter.selected.first { $0.id == placeID }
    }

    private var dayChoice: Binding<String> {
        Binding(get: {
            let options = presenter.planning.enginePreferences
            if options?.scheduleSource == .manual || options?.scheduleSource == .resolved { return "selected_date" }
            return options?.tripTiming?.rawValue ?? "automatic"
        }, set: { value in
            if value == "selected_date" {
                presenter.planning.enginePreferences?.scheduleSource = .manual
                presenter.planning.enginePreferences?.usesAutomaticTripDate = false
            } else { presenter.chooseTripTiming(PlanningTripTiming(rawValue: value)) }
        })
    }

    private func changeTripDate(to date: Date) {
        presenter.changeTripDate(date)
    }

    var body: some View {
        @Bindable var planning = presenter.planning
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    if let focusedVisit {
                        Section("Visit to review") { visitFields(focusedVisit) }
                    }
                    Section("Available time") {
                        if presenter.usesV41 {
                            Picker("Choose day", selection: dayChoice) {
                                Text("Selected date").tag("selected_date")
                                Text("Automatic").tag("automatic")
                                Text("Today").tag(PlanningTripTiming.now.rawValue)
                                Text("Tomorrow").tag(PlanningTripTiming.tomorrow.rawValue)
                                Text("In 2–3 days").tag(PlanningTripTiming.inAFewDays.rawValue)
                                Text("Compare today and the next 2 days").tag(PlanningTripTiming.bestDay.rawValue)
                            }
                            .accessibilityIdentifier("tripTimingChoice")
                        }
                        DatePicker("Trip date", selection: Binding(get: { planning.startsAt }, set: changeTripDate),
                                   displayedComponents: .date)
                            .accessibilityIdentifier("tripScheduleDate")
                        DatePicker("Earliest departure", selection: Binding(get: { planning.startsAt }, set: {
                            planning.startsAt = $0
                            planning.enginePreferences?.usesAutomaticTripDate = false
                            planning.enginePreferences?.scheduleSource = .manual
                        }), displayedComponents: .hourAndMinute)
                        DatePicker("Finish by", selection: Binding(get: { planning.finishBy }, set: {
                            planning.finishBy = $0
                            planning.enginePreferences?.usesAutomaticTripDate = false
                            planning.enginePreferences?.scheduleSource = .manual
                        }), displayedComponents: .hourAndMinute)
                            .id(ScheduleField.finish)
                            .accessibilityFocused($focusedField, equals: .finish)
                        if planning.finishBy <= planning.startsAt || !calendar.isDate(planning.startsAt, inSameDayAs: planning.finishBy) {
                            Text("Choose a finish time after departure on the same day.").foregroundStyle(.red)
                        }
                    }
                    if let options = Binding($planning.enginePreferences) {
                        Section("Schedule preferences") {
                            Toggle("Flexible departure", isOn: options.flexibleDeparture)
                            if let name = options.wrappedValue.endPointName {
                                LabeledContent("End point", value: name)
                                Button("Remove custom end point") {
                                    planning.enginePreferences?.endPoint = nil
                                    planning.enginePreferences?.endPointName = nil
                                    planning.draftChanged()
                                }
                            } else {
                                Toggle("Return to starting point", isOn: options.returnToOrigin)
                            }
                            if presenter.usesV41 {
                                Button("Choose a custom end point") { choosesEndpoint = true }
                            }
                            Stepper("Maximum waiting: \(options.wrappedValue.maximumWaitMinutes) min", value: options.maximumWaitMinutes, in: 0 ... 120, step: 5)
                                .id(ScheduleField.waiting)
                                .accessibilityFocused($focusedField, equals: .waiting)
                            if options.wrappedValue.orderingMethod?.usesV5Scheduler == true {
                                Stepper("Check-in buffer: \(options.wrappedValue.checkInBufferMinutes ?? 15) min",
                                        value: Binding(get: { options.wrappedValue.checkInBufferMinutes ?? 15 },
                                                       set: { options.wrappedValue.checkInBufferMinutes = $0 }), in: 0 ... 120)
                                    .accessibilityIdentifier("checkInBufferTarget")
                                Stepper("Extra travel allowed: \(options.wrappedValue.extraTravelMinutes ?? 0) min",
                                        value: Binding(get: { options.wrappedValue.extraTravelMinutes ?? 0 },
                                                       set: { options.wrappedValue.extraTravelMinutes = $0 }), in: 0 ... 120)
                                    .accessibilityIdentifier("extraTravelAllowance")
                                Toggle("Avoid rain during outdoor visits", isOn: options.avoidRain)
                            }
                            if presenter.usesV41 {
                                Picker("Preferred visit period", selection: Binding(get: { options.wrappedValue.preferredDayPart }, set: {
                                    options.wrappedValue.preferredDayPart = $0
                                    presenter.answers.dayPart = $0.flatMap { DayPart(rawValue: $0.rawValue) }
                                })) {
                                    Text("Any time").tag(PlanningDayPart?.none)
                                    Text("Morning · 06–11").tag(Optional(PlanningDayPart.morning))
                                    Text("Midday · 11–15").tag(Optional(PlanningDayPart.afternoon))
                                    Text("Afternoon · 15–18").tag(Optional(PlanningDayPart.evening))
                                    Text("Night · 18–22").tag(Optional(PlanningDayPart.night))
                                }
                                if !presenter.planning.requiresExternalAIConsent || presenter.planning.externalAIAvailable {
                                    modelAssistance(options)
                                }
                            }
                        }
                    }
                    let otherPlaces = presenter.selected.filter { $0.id != focusedVisit?.id }
                    if !otherPlaces.isEmpty {
                        Section("Visit durations") {
                            ForEach(otherPlaces) { item in visitFields(item) }
                        }
                    }
                }
                .environment(\.timeZone, zone)
                .navigationTitle("Trip schedule")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if let firstInvalidField {
                            Button("Review error") { reveal(firstInvalidField, scroll: scroll) }
                                .accessibilityHint("Go to the first field to fix before saving")
                        } else {
                            Button("Done") { planning.draftChanged(); dismiss() }
                        }
                    }
                }
                .task {
                    if let field = target ?? firstInvalidField { reveal(field, scroll: scroll) }
                }
                .task(id: revealedField) {
                    guard let revealedField else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scroll.scrollTo(revealedField, anchor: .center)
                    focusedField = revealedField
                }
            }
        }
        .fullScreenCover(isPresented: $choosesEndpoint) {
            PlanningSearchSheet(near: planning.origin, title: "End point") { place in
                planning.enginePreferences?.endPoint = place.location
                planning.enginePreferences?.endPointName = place.name
                planning.draftChanged()
                choosesEndpoint = false
            }
        }
    }

    private func visitFields(_ item: RecommendedPlace) -> some View {
        let id = item.id
        let override = item.place.durationOverridden == true
        let field = revealedField ?? target
        let showAccessFirst = field == .access(id) || field == .entry(id) || field == .session(id) || field == .checkIn(id)
        return VStack(alignment: .leading) {
            Text(item.place.name)
            if presenter.planning.enginePreferences?.orderingMethod?.usesV5Scheduler == true {
                VisitExposurePicker(exposure: Binding(get: {
                    presenter.selected.first { $0.id == id }?.place.visitExposure ?? .unknown
                }, set: { presenter.setVisitExposure(id, exposure: $0) }))
                .accessibilityIdentifier("visitExposure-\(id)")
            }
            if presenter.usesV41, showAccessFirst { visitAccess(id, field: field) }
            Toggle("Set visit duration", isOn: Binding(get: {
                presenter.selected.first(where: { $0.id == id })?.place.durationOverridden == true
            }, set: {
                presenter.setVisitDuration(id, minutes: $0 ? max(15, item.place.visitSeconds / 60) : nil)
            }))
            .id(ScheduleField.duration(id))
            .accessibilityFocused($focusedField, equals: .duration(id))
            if override {
                Stepper("\(item.place.visitSeconds / 60) min", value: Binding(get: {
                    (presenter.selected.first(where: { $0.id == id })?.place.visitSeconds ?? 2700) / 60
                }, set: { presenter.setVisitDuration(id, minutes: $0) }), in: 15 ... 240, step: 5)
                if presenter.usesV41 {
                    Toggle("Allow a shorter visit", isOn: Binding(get: { item.place.minimumAcceptedVisitSeconds != nil }, set: {
                        presenter.setMinimumDuration(id, minutes: $0 ? max(15, item.place.visitSeconds / 120) : nil)
                    }))
                    if let minimum = item.place.minimumAcceptedVisitSeconds {
                        Stepper("Minimum \(minimum / 60) min", value: Binding(get: { minimum / 60 }, set: {
                            presenter.setMinimumDuration(id, minutes: $0)
                        }), in: 15 ... max(15, item.place.visitSeconds / 60), step: 5)
                    }
                }
            } else if presenter.usesV41, presenter.planning.enginePreferences?.semanticAssistance == .disabled {
                Text("Set a duration when visit suggestions are off.").font(.footnote).foregroundStyle(.secondary)
            } else if presenter.usesFoundationModels {
                Text("Use an on-device estimate when available.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Use Luna's estimate when available.").font(.footnote).foregroundStyle(.secondary)
            }
            if presenter.usesV41, !showAccessFirst { visitAccess(id, field: field) }
        }
        .id(ScheduleField.place(id))
    }

    private func visitAccess(_ id: UUID, field: ScheduleField?) -> some View {
        V41VisitAccessFields(presenter: presenter, placeID: id, revealedField: field, focus: $focusedField)
    }

    @ViewBuilder private func modelAssistance(_ options: Binding<PlanningPreferences>) -> some View {
        let title: LocalizedStringKey = presenter.usesFoundationModels ? "Foundation Models assistance" : "Luna assistance"
        let identifier = presenter.usesFoundationModels ? "foundationModelsAssistance" : "lunaAssistance"
        let picker = Picker(title, selection: Binding(get: { options.wrappedValue.semanticAssistance ?? .whenNeeded }, set: {
            options.wrappedValue.semanticAssistance = $0
            if !presenter.usesFoundationModels { options.wrappedValue.usesLuna = $0 != .disabled }
            if presenter.planning.requiresExternalAIConsent && $0 == .disabled {
                options.wrappedValue.externalAIConsentID = nil
            }
            options.wrappedValue.allowsAIProcessing = $0 != .disabled &&
                (!presenter.planning.requiresExternalAIConsent || presenter.usesFoundationModels ||
                 options.wrappedValue.externalAIConsentID != nil)
        })) {
            Text("Estimate missing durations").fixedSize(horizontal: false, vertical: true).tag(PlanningSemanticAssistance.whenNeeded)
            Text("Activities and preferred times").fixedSize(horizontal: false, vertical: true).tag(PlanningSemanticAssistance.requested)
            Text("Off · use my durations").fixedSize(horizontal: false, vertical: true).tag(PlanningSemanticAssistance.disabled)
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.inline).accessibilityIdentifier(identifier)
        } else {
            picker.accessibilityIdentifier(identifier)
        }
    }

    private func reveal(_ field: ScheduleField, scroll: ScrollViewProxy) {
        revealedField = field
        scroll.scrollTo(field.placeID.map(ScheduleField.place) ?? field, anchor: .center)
        focusedField = field
    }
}

private struct V41VisitAccessFields: View {
    @Bindable var presenter: TripCreationPresenter
    let placeID: UUID
    let revealedField: ScheduleField?
    var focus: AccessibilityFocusState<ScheduleField?>.Binding
    @State private var expanded = false

    var body: some View {
        if let place = presenter.selected.first(where: { $0.id == placeID })?.place {
            DisclosureGroup("Access and activity session", isExpanded: $expanded) {
                Toggle("I confirmed access during this trip window", isOn: Binding(get: { place.visitConfirmation != nil }, set: { enabled in
                    if enabled {
                        presenter.confirmVisit(placeID, opens: presenter.planning.startsAt, closes: presenter.planning.finishBy, publicAccess: true)
                    } else { presenter.clearVisitConfirmation(placeID) }
                }))
                .id(place.visitConfirmation == nil ? ScheduleField.access(placeID) : nil)
                .accessibilityFocused(focus, equals: place.visitConfirmation == nil ? .access(placeID) : nil)
                if let access = place.visitConfirmation {
                    if access.opensAt >= access.closesAt {
                        Text("Available until must be after available from.").foregroundStyle(.red)
                    }
                    if let cutoff = access.lastEntryAt, cutoff < access.opensAt || cutoff > access.closesAt {
                        Text("Last entry must be within the confirmed access window.").foregroundStyle(.red)
                    }
                    DatePicker("Available from", selection: Binding(get: { access.opensAt }, set: {
                        presenter.confirmVisit(placeID, opens: $0, closes: access.closesAt, publicAccess: true)
                    }), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Available until", selection: Binding(get: { access.closesAt }, set: {
                        presenter.confirmVisit(placeID, opens: access.opensAt, closes: $0, publicAccess: true)
                    }), displayedComponents: [.date, .hourAndMinute])
                        .id(Optional(ScheduleField.access(placeID)))
                        .accessibilityFocused(focus, equals: .access(placeID))
                    Toggle("Last entry applies", isOn: Binding(get: { access.lastEntryAt != nil }, set: {
                        presenter.setEntryCutoff(placeID, date: $0 ? access.closesAt : nil)
                    }))
                    .id(access.lastEntryAt == nil ? ScheduleField.entry(placeID) : nil)
                    .accessibilityFocused(focus, equals: access.lastEntryAt == nil ? .entry(placeID) : nil)
                    if let cutoff = access.lastEntryAt {
                        DatePicker("Last entry", selection: Binding(get: { cutoff }, set: { presenter.setEntryCutoff(placeID, date: $0) }), displayedComponents: .hourAndMinute)
                            .id(Optional(ScheduleField.entry(placeID)))
                            .accessibilityFocused(focus, equals: .entry(placeID))
                    }
                }
                Toggle("I have a booked activity session", isOn: Binding(get: { place.activitySession != nil }, set: {
                    let start = presenter.planning.startsAt
                    presenter.setActivitySession(placeID, session: $0 ? .init(startsAt: start, endsAt: start.addingTimeInterval(3600)) : nil)
                }))
                .id(place.activitySession == nil ? ScheduleField.session(placeID) : nil)
                .accessibilityFocused(focus, equals: place.activitySession == nil ? .session(placeID) : nil)
                if let session = place.activitySession {
                    if session.startsAt >= session.endsAt {
                        Text("Session end must be after the start.").foregroundStyle(.red)
                    }
                    if let cutoff = session.arriveBy, cutoff > session.startsAt {
                        Text("Check-in must be no later than the session start.").foregroundStyle(.red)
                    }
                    DatePicker("Session starts", selection: Binding(get: { session.startsAt }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: $0, endsAt: session.endsAt, arriveBy: session.arriveBy))
                    }), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Session ends", selection: Binding(get: { session.endsAt }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: $0, arriveBy: session.arriveBy))
                    }), displayedComponents: [.date, .hourAndMinute])
                        .id(Optional(ScheduleField.session(placeID)))
                        .accessibilityFocused(focus, equals: .session(placeID))
                    Toggle("Session has a check-in deadline", isOn: Binding(get: { session.arriveBy != nil }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: session.endsAt, arriveBy: $0 ? session.startsAt : nil))
                    }))
                    .id(session.arriveBy == nil ? ScheduleField.checkIn(placeID) : nil)
                    .accessibilityFocused(focus, equals: session.arriveBy == nil ? .checkIn(placeID) : nil)
                    if let cutoff = session.arriveBy {
                        DatePicker("Arrive by", selection: Binding(get: { cutoff }, set: {
                            presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: session.endsAt, arriveBy: $0))
                        }), displayedComponents: .hourAndMinute)
                            .id(Optional(ScheduleField.checkIn(placeID)))
                            .accessibilityFocused(focus, equals: .checkIn(placeID))
                    }
                }
            }
            .onChange(of: revealedField, initial: true) { _, field in
                if field == .access(placeID) || field == .entry(placeID) ||
                    field == .session(placeID) || field == .checkIn(placeID) { expanded = true }
            }
        }
    }
}
