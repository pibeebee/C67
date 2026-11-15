import SwiftUI

struct TripEmptyView: View {
    var planTrip: () -> Void = {}

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 86))
                .foregroundStyle(AppColor.brand)
                .frame(width: 168, height: 168)
                .background(AppColor.surface, in: .circle)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Haven’t checked out any cool spots yet?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Let’s plan your next trip!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("homeEmptyState")
            Button(action: planTrip) {
                Label("Plan a Trip", systemImage: "plus")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppColor.brand)
            .controlSize(.large)
            .accessibilityIdentifier("homePlanTrip")
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
    }
}

#Preview {
    TripEmptyView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("TripCanvas"))
}
