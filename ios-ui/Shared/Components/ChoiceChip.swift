import SwiftUI

/// Capsule toggle for multi-select answers, with an optional SF Symbol.
struct ChoiceChip: View {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
        }
        .buttonStyle(ChoiceChipButtonStyle(isSelected: isSelected))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
