import SwiftUI

/// A full-width selectable row with an optional leading view, a title, a subtitle and a trailing
/// checkmark when selected, like a native picker row.
struct CheckmarkRow<Leading: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let titleFont: Font
    private let isSelected: Bool
    private let action: () -> Void
    private let leading: Leading

    init(
        title: Text,
        subtitle: Text? = nil,
        titleFont: Font = AppFont.body,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.isSelected = isSelected
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                leading
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(titleFont)
                        .foregroundStyle(AppColor.primaryText)
                    if let subtitle {
                        subtitle
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension CheckmarkRow where Leading == EmptyView {
    init(
        title: Text,
        subtitle: Text? = nil,
        titleFont: Font = AppFont.body,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, titleFont: titleFont, isSelected: isSelected, action: action) {
            EmptyView()
        }
    }
}
