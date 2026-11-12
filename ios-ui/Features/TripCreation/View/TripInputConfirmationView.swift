import SwiftUI
import C67Domain

struct TripInputConfirmationView: View {
    @Bindable var presenter: TripCreationPresenter
    let confirm: () -> Void
    @State private var searchesOrigin = false

    var body: some View {
        @Bindable var planning = presenter.planning
        Form {
            Section {
                Text("Confirm the details used to plan your itinerary.")
                if presenter.mode.hasPrefix("Mock") { Text("Synthetic demonstration · trips last until the app closes.").font(.footnote) }
            }
            Section("Starting point") {
                Text(planning.originLabel)
                Button("Choose starting point", systemImage: "location.magnifyingglass") { searchesOrigin = true }
            }
            Section("Required places") {
                ForEach(presenter.selected) { item in Text(item.place.name) }
                Button(presenter.selected.isEmpty ? "Choose at least one place" : "Edit places", systemImage: "plus") { presenter.push(.places) }
                Text("Choose one to six places. Recommendations are optional additions.").font(.footnote)
            }
            Section("Trip details") {
                TextField("Trip name", text: $planning.title)
                    .accessibilityIdentifier("tripInputTitle")
                DatePicker("Depart", selection: $planning.startsAt)
                DatePicker("Finish by", selection: $planning.finishBy)
                TextField("Time zone", text: $planning.timeZone)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Routing mode", selection: $planning.mode) {
                    Text("Walking").tag(C67Domain.PlanningMode.walking)
                    Text("Driving").tag(C67Domain.PlanningMode.automobile)
                }
                Text("Transport and timing answers are preferences. This planner requires a confirmed date, time and walking or driving route.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Continue", action: confirm)
                    .disabled(!presenter.canConfirm)
                    .accessibilityIdentifier("confirmTripInput")
                if !presenter.canConfirm {
                    Text("Choose a starting point and at least one place, a nonempty name, and a finish time within 24 hours of departure.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: planning.timeZone) ?? .current)
        .navigationTitle("Confirm your trip")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $searchesOrigin) {
            PlanningSearchSheet(near: planning.origin, title: "Starting point") { place in
                planning.origin = place.location
                planning.originLabel = place.name
                planning.draftChanged()
            }
        }
    }
}
