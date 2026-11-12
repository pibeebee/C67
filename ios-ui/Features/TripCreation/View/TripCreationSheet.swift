import SwiftUI

/// Read the draft through a binding so the sheet receives the model set in the same action
/// that presents it, including its very first presentation.
struct TripCreationSheet: View {
    @Binding var presenter: TripCreationPresenter?
    let dismiss: () -> Void

    var body: some View {
        if let presenter { TripCreationView(presenter: presenter, dismiss: dismiss) }
    }
}
