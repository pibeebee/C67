import SwiftUI

struct TripLocationButton: View {
    let title: String
    var isLocating = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(isLocating ? String(localized: "Locating…") : title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !isLocating {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modifier(TripGlassCapsule())
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocating ? Text("Locating your position") : Text("Starting point: \(title)"))
        .accessibilityHint("Choose a starting point for your trip")
        .accessibilityIdentifier("homeLocation")
    }
}
