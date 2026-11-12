import SwiftUI

/// Capsule toggle with an SF Symbol, used for multi-select answers.
struct ChoiceChip: View {
    let title: LocalizedStringResource
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
        }
        .buttonStyle(ChoiceChipButtonStyle(isSelected: isSelected))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
