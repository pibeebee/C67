import SwiftUI

/// Full-width capsule action at the bottom of a question, such as Next.
///
/// Uses the native prominent button style, so the disabled state comes from `.disabled(_:)`.
struct QuestionPrimaryButton: View {
    private let title: LocalizedStringKey
    private let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(AppColor.brand)
    }
}
