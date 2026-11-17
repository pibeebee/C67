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
            calendar.isDate(presenter.planning.startsAt, inSameDayAs: presenter.planning.finishBy)
    }

    private func changeTripDate(to date: Date) {
        let planning = presenter.planning
        let day = calendar.startOfDay(for: date)
        let currentDay = calendar.startOfDay(for: planning.startsAt)
        guard let days = calendar.dateComponents([.day], from: currentDay, to: day).day, days != 0,
              let start = calendar.date(byAdding: .day, value: days, to: planning.startsAt),
              let finish = calendar.date(byAdding: .day, value: days, to: planning.finishBy) else { return }
        planning.startsAt = start
        planning.finishBy = finish
        planning.enginePreferences?.usesAutomaticTripDate = false
    }

    var body: some View {
        @Bindable var planning = presenter.planning
        NavigationStack {
            Form {
                Section("Available time") {
                    DatePicker("Trip date", selection: Binding(get: { planning.startsAt }, set: changeTripDate),
                               displayedComponents: .date)
                        .accessibilityIdentifier("tripScheduleDate")
                    DatePicker("Earliest departure", selection: Binding(get: { planning.startsAt }, set: {
                        planning.startsAt = $0
                        planning.enginePreferences?.usesAutomaticTripDate = false
                    }), displayedComponents: .hourAndMinute)
                    DatePicker("Finish by", selection: Binding(get: { planning.finishBy }, set: {
                        planning.finishBy = $0
                        planning.enginePreferences?.usesAutomaticTripDate = false
                    }), displayedComponents: .hourAndMinute)
                    if !validWindow { Text("Choose a finish time after departure on the same day.").foregroundStyle(.red) }
                }
                if let options = Binding($planning.enginePreferences) {
                    Section("Schedule preferences") {
                        Toggle("Flexible departure", isOn: options.flexibleDeparture)
                        Toggle("Return to starting point", isOn: options.returnToOrigin)
                        Stepper("Maximum waiting: \(options.wrappedValue.maximumWaitMinutes) min", value: options.maximumWaitMinutes, in: 0 ... 120, step: 5)
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
                            } else { Text("Use Luna's estimate when available.").font(.footnote).foregroundStyle(.secondary) }
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
