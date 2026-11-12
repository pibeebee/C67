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
            Section(planning.supportsOnDevicePlanning ? "Places to keep" : "Required places") {
                ForEach(presenter.selected) { item in Text(item.place.name) }
                if planning.supportsOnDevicePlanning && !presenter.selected.isEmpty {
                    Button("Visit times and availability") { presenter.push(.availability) }
                }
                Button(presenter.selected.isEmpty ? (planning.supportsOnDevicePlanning ? "Add a specific place" : "Choose at least one place") : "Edit places", systemImage: "plus") { presenter.push(.places) }
                Text(planning.supportsOnDevicePlanning ? "You can request recommendations without a required place. Select the places to visit before planning." : "Choose one to six places. Recommendations are optional additions.").font(.footnote)
            }
            Section("Trip details") {
                TextField("Trip name", text: $planning.title)
                    .accessibilityIdentifier("tripInputTitle")
                DatePicker("Depart", selection: $planning.startsAt)
                DatePicker("Finish by", selection: $planning.finishBy)
                if planning.supportsOnDevicePlanning { Text("Jakarta time · WIB") }
                else {
                    TextField("Time zone", text: $planning.timeZone)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Picker("Routing mode", selection: $planning.mode) {
                    Text("Walking").tag(C67Domain.PlanningMode.walking)
                    Text("Driving").tag(C67Domain.PlanningMode.automobile)
                }
                Text("Transport and timing answers are preferences. This planner requires a confirmed date, time and walking or driving route.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if planning.supportsOnDevicePlanning { PocketTripOptionsView(presenter: presenter) }
            Section {
                QuestionPrimaryButton("Continue", action: confirm)
                    .disabled(!presenter.canConfirm)
                    .accessibilityIdentifier("confirmTripInput")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                if !presenter.canConfirm {
                    Text(planning.supportsOnDevicePlanning
                        ? "Choose a starting point, a trip name, and a departure and finish time. Plan visits on a single day in Jakarta time."
                        : "Choose a starting point and at least one place, a nonempty name, and a finish time within 24 hours of departure.")
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

#if DEBUG
    import C67Data

    #Preview("Confirm your trip · Continue") {
        let planning = PlanningPresenter(interactor: .init(repository: MockPlanningRepository()),
                                         initialInput: try? MockPlanningRepository.sampleInput())
        let presenter = TripCreationAssembly.makePresenter(planning: planning, mode: "Mock • memory only", specificPlace: true)
        NavigationStack {
            TripInputConfirmationView(presenter: presenter, confirm: {})
        }
    }
#endif
