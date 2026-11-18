import SwiftUI
import C67Domain

struct PocketConnectionView: View {
    @Bindable var presenter: PlanningPresenter
    let dismiss: () -> Void
    @State private var serverURL = ""
    @State private var token = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                ItineraryMethodSection()
                Section("Pocket connection") {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("pocketServerURL")
                    SecureField(presenter.pocketConnection?.hasToken == true ? "New read token (leave empty to keep)" : "Pocket read token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("pocketReadToken")
                    Button(presenter.isSavingConnection ? "Saving…" : "Save connection") {
                        Task {
                            saved = await presenter.savePocketConnection(serverURL: serverURL, token: token)
                            if saved { token = "" }
                        }
                    }
                    .disabled(presenter.isSavingConnection || serverURL.isEmpty)
                    .accessibilityIdentifier("pocketSaveConnection")
                    if saved { Text("Saved securely. Connectivity has not been checked.").font(.footnote) }
                    if let error = presenter.connectionError { Text(error).foregroundStyle(.red) }
                }
                Section("How your trip is processed") {
                    Text("The Pocket server sends your selected places and preferences to Luna for itinerary recommendations.")
                    Text("Your saved trips stay in this app on this device. Account sync is not enabled in Pocket mode.")
                    Text("Use HTTPS for TestFlight. API provider keys and the server write token must stay on the server.")
                }
            }
            .navigationTitle("Pocket settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
            .task {
                await presenter.loadPocketConnection()
                serverURL = presenter.pocketConnection?.serverURL ?? ""
            }
        }
    }
}

struct ItineraryMethodSection: View {
    @AppStorage("io.pibeebee.c67.orderingMethod") private var orderingMethod = PlanningOrderingMethod.luna.rawValue

    var body: some View {
        Section("Itinerary method") {
            Picker("Method", selection: $orderingMethod) {
                Text("Luna").tag(PlanningOrderingMethod.luna.rawValue)
                Text("Hybrid v4: schedules").tag(PlanningOrderingMethod.hybridV4.rawValue)
                Text("Hybrid v4.1: flexible schedules").tag(PlanningOrderingMethod.hybridV41.rawValue)
                Text("Hybrid v4.2: faster planning").tag(PlanningOrderingMethod.hybridV42.rawValue)
                Text("Hybrid: weather context").tag(PlanningOrderingMethod.hybridWeather.rawValue)
            }
            .accessibilityIdentifier("pocketOrderingMethod")
            .onAppear { if orderingMethod == PlanningOrderingMethod.hybridLegacy.rawValue { orderingMethod = PlanningOrderingMethod.hybridWeather.rawValue } }
            Text("Luna assistance uses the Pocket server. Hybrid v4.1 and v4.2 can schedule your supplied visit durations directly using estimated travel and available hours.")
                .font(.footnote)
        }
    }
}
