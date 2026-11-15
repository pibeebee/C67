import SwiftUI

/// Read the draft through a binding so navigation receives the model created when the flow starts.
struct TripCreationSheet: View {
    @Binding var presenter: TripCreationPresenter?
    let dismiss: () -> Void
    var openPocketSettings: (() -> Void)?

    var body: some View {
        if let presenter { TripCreationView(presenter: presenter, dismiss: dismiss, openPocketSettings: openPocketSettings) }
    }
}
