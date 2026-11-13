import SwiftUI

/// The two-line empty state from Sketch HI-FI / HOME EMPTY.
struct TripEmptyView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Your luggage is crying in the corner")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Give it a reason to travel. Let’s plan a trip!")
                .font(.body)
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeEmptyState")
    }
}

#Preview {
    TripEmptyView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("TripCanvas"))
}
