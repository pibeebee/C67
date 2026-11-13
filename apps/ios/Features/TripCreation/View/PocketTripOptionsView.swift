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
        Section("Visit area") {
            Picker("Area", selection: $options.area) {
                Text("Jakarta Selatan").tag("jakarta-selatan")
                Text("Kemayoran").tag("kemayoran")
            }
            .accessibilityIdentifier("pocketArea")
            Text("Recommendations and selected destinations stay inside this area's sourced boundary.").font(.footnote)
        }
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
        Section("Schedule advice") {
            Toggle("Use Luna Max", isOn: $options.usesLuna)
                .accessibilityIdentifier("pocketUseLuna")
            if options.usesLuna {
                Toggle("Allow sharing place names and schedule options", isOn: $options.allowsAIProcessing)
                    .accessibilityIdentifier("pocketAIConsent")
                Text("The configured Pocket server sends your selected places, interests and schedule options to the configured Luna Max provider. Your starting-point coordinates and server token are not included in the model request. Luna can select an existing valid schedule; it cannot supply new venue facts or route times.")
                    .font(.footnote)
            }
        }
    }
}
