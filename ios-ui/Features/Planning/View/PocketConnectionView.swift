import SwiftUI

struct PocketConnectionView: View {
    @Bindable var presenter: PlanningPresenter
    let dismiss: () -> Void
    @State private var serverURL = ""
    @State private var token = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pocket connection") {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("pocketServerURL")
                    SecureField(presenter.pocketConnection?.hasToken == true ? "New read token (leave empty to keep)" : "Catalog read token", text: $token)
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
                    Text("Preferences, matching and schedule validation run on this device. The server supplies the independent catalog and, when you allow it, Luna Max schedule advice.")
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
