import SwiftUI

/// Full-width answer button for single-choice questions.
///
/// Unselected answers use the adaptive surface; the selected answer uses the brand fill
/// with white text. The whole rounded rectangle is the tap target.
struct ChoiceOptionButtonStyle: ButtonStyle {
    var isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(isSelected ? AppColor.onBrand : AppColor.primaryText)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(isSelected ? AppColor.brand : AppColor.surface, in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
