import SwiftUI

struct TripAddButton: View {
    let action: () -> Void
    var addSpecificPlace: () -> Void = {}

    var body: some View {
        if #available(iOS 26.0, *) {
            menu
                .menuStyle(.button)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityIdentifier("homeAddTrip")
        } else {
            menu
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityIdentifier("homeAddTrip")
        }
    }

    private var menu: some View {
        Menu {
            Button("Get Recommendations", action: action)
            Button("Add Specific Place", action: addSpecificPlace)
        } label: {
            Label("Plan a trip", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}
