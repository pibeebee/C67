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
            Text("Travelant researches the selected place names, pins, available branch details and preferences using the Pocket server and Luna. Opening hours and entry rules require retrieved sources; suggested durations remain estimates. Apple provides driving times.")
                .font(.footnote)
        }
    }
}

/// Trip constraints available before the first scheduler request.
struct PocketScheduleOptionsSheet: View {
    @Bindable var presenter: TripCreationPresenter
    @Environment(\.dismiss) private var dismiss

    private var zone: TimeZone { TimeZone(identifier: presenter.planning.timeZone) ?? .current }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private var validWindow: Bool {
        return presenter.planning.finishBy > presenter.planning.startsAt &&
            calendar.isDate(presenter.planning.startsAt, inSameDayAs: presenter.planning.finishBy) &&
            presenter.selected.allSatisfy { item in
                if let access = item.place.visitConfirmation {
                    if access.opensAt >= access.closesAt { return false }
                    if let cutoff = access.lastEntryAt, cutoff < access.opensAt || cutoff > access.closesAt { return false }
                }
                guard let session = item.place.activitySession else { return true }
                return session.startsAt < session.endsAt && (session.arriveBy == nil || session.arriveBy! <= session.startsAt)
            }
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
            Form {
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
                    if !validWindow { Text("Choose a finish time after departure on the same day.").foregroundStyle(.red) }
                }
                if let options = Binding($planning.enginePreferences) {
                    Section("Schedule preferences") {
                        Toggle("Flexible departure", isOn: options.flexibleDeparture)
                        Toggle("Return to starting point", isOn: options.returnToOrigin)
                        Stepper("Maximum waiting: \(options.wrappedValue.maximumWaitMinutes) min", value: options.maximumWaitMinutes, in: 0 ... 120, step: 5)
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
                            Picker("Luna assistance", selection: Binding(get: { options.wrappedValue.semanticAssistance ?? .whenNeeded }, set: {
                                options.wrappedValue.semanticAssistance = $0
                                options.wrappedValue.usesLuna = $0 != .disabled
                                options.wrappedValue.allowsAIProcessing = $0 != .disabled
                            })) {
                                Text("Estimate missing durations").tag(PlanningSemanticAssistance.whenNeeded)
                                Text("Activities and preferred times").tag(PlanningSemanticAssistance.requested)
                                Text("Off · use my durations").tag(PlanningSemanticAssistance.disabled)
                            }
                            .accessibilityIdentifier("lunaAssistance")
                        }
                    }
                }
                Section("Visit durations") {
                    ForEach(presenter.selected) { item in
                        let id = item.id
                        let override = item.place.durationOverridden == true
                        VStack(alignment: .leading) {
                            Text(item.place.name)
                            Toggle("Set visit duration", isOn: Binding(get: { presenter.selected.first(where: { $0.id == id })?.place.durationOverridden == true }, set: { presenter.setVisitDuration(id, minutes: $0 ? max(15, item.place.visitSeconds / 60) : nil) }))
                            if override {
                                Stepper("\(item.place.visitSeconds / 60) min", value: Binding(get: { (presenter.selected.first(where: { $0.id == id })?.place.visitSeconds ?? 2700) / 60 }, set: { presenter.setVisitDuration(id, minutes: $0) }), in: 15 ... 240, step: 5)
                                if presenter.usesV41 {
                                    Toggle("Allow a shorter visit", isOn: Binding(get: { item.place.minimumAcceptedVisitSeconds != nil }, set: {
                                        presenter.setMinimumDuration(id, minutes: $0 ? max(15, item.place.visitSeconds / 120) : nil)
                                    }))
                                    if let minimum = item.place.minimumAcceptedVisitSeconds {
                                        Stepper("Minimum \(minimum / 60) min", value: Binding(get: { minimum / 60 }, set: { presenter.setMinimumDuration(id, minutes: $0) }), in: 15 ... max(15, item.place.visitSeconds / 60), step: 5)
                                    }
                                }
                            } else { Text("Use Luna's estimate when available.").font(.footnote).foregroundStyle(.secondary) }
                            if presenter.usesV41 { V41VisitAccessFields(presenter: presenter, placeID: id) }
                        }
                    }
                }
            }
            .environment(\.timeZone, zone)
            .navigationTitle("Trip schedule")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { planning.draftChanged(); dismiss() }.disabled(!validWindow) } }
        }
    }
}

private struct V41VisitAccessFields: View {
    @Bindable var presenter: TripCreationPresenter
    let placeID: UUID

    var body: some View {
        if let place = presenter.selected.first(where: { $0.id == placeID })?.place {
            DisclosureGroup("Access and activity session") {
                Toggle("I confirmed access during this trip window", isOn: Binding(get: { place.visitConfirmation != nil }, set: { enabled in
                    if enabled {
                        presenter.confirmVisit(placeID, opens: presenter.planning.startsAt, closes: presenter.planning.finishBy, publicAccess: true)
                    } else { presenter.clearVisitConfirmation(placeID) }
                }))
                if let access = place.visitConfirmation {
                    DatePicker("Available from", selection: Binding(get: { access.opensAt }, set: {
                        presenter.confirmVisit(placeID, opens: $0, closes: access.closesAt, publicAccess: true)
                    }), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Available until", selection: Binding(get: { access.closesAt }, set: {
                        presenter.confirmVisit(placeID, opens: access.opensAt, closes: $0, publicAccess: true)
                    }), displayedComponents: [.date, .hourAndMinute])
                    Toggle("Last entry applies", isOn: Binding(get: { access.lastEntryAt != nil }, set: {
                        presenter.setEntryCutoff(placeID, date: $0 ? access.closesAt : nil)
                    }))
                    if let cutoff = access.lastEntryAt {
                        DatePicker("Last entry", selection: Binding(get: { cutoff }, set: { presenter.setEntryCutoff(placeID, date: $0) }), displayedComponents: .hourAndMinute)
                    }
                }
                Toggle("I have a booked activity session", isOn: Binding(get: { place.activitySession != nil }, set: {
                    let start = presenter.planning.startsAt
                    presenter.setActivitySession(placeID, session: $0 ? .init(startsAt: start, endsAt: start.addingTimeInterval(3600)) : nil)
                }))
                if let session = place.activitySession {
                    DatePicker("Session starts", selection: Binding(get: { session.startsAt }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: $0, endsAt: session.endsAt, arriveBy: session.arriveBy))
                    }), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Session ends", selection: Binding(get: { session.endsAt }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: $0, arriveBy: session.arriveBy))
                    }), displayedComponents: [.date, .hourAndMinute])
                    Toggle("Session has a check-in deadline", isOn: Binding(get: { session.arriveBy != nil }, set: {
                        presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: session.endsAt, arriveBy: $0 ? session.startsAt : nil))
                    }))
                    if let cutoff = session.arriveBy {
                        DatePicker("Arrive by", selection: Binding(get: { cutoff }, set: {
                            presenter.setActivitySession(placeID, session: .init(startsAt: session.startsAt, endsAt: session.endsAt, arriveBy: $0))
                        }), displayedComponents: .hourAndMinute)
                    }
                }
            }
        }
    }
}
