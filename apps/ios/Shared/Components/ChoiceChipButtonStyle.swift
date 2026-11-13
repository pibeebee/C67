import SwiftUI

/// Capsule style for multi-select chips, matching Sketch
/// `Buttons/Light/Large/Bordered/Text` (unselected) and its brand-filled selected override.
///
/// Unselected chips use the translucent tertiary fill; selected chips use the brand fill with
/// white content. Padding follows the symbol: 16 pt vertical, 20 pt horizontal.
struct ChoiceChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body)
            .foregroundStyle(isSelected ? AppColor.onBrand : AppColor.primaryText)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(isSelected ? AppColor.brand : AppColor.tertiaryFill, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
