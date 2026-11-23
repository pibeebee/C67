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
        Button(title, action: action)
            .buttonStyle(TripPrimaryButtonStyle())
    }
}

/// Native full-width primary action used throughout the trip flow.
struct TripPrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(AppColor.brand)
        // Keep scrolled content from showing through the native disabled fill.
        .background(AppColor.canvas, in: .capsule)
    }
}
