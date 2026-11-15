import SwiftUI

/// Full-screen wait state: a bold headline, a message with highlighted words and the native
/// large spinner. Matches the Sketch HI-FI `PREFERENCES PROCESSING` frames.
///
/// Only an indeterminate spinner is shown, because the work has no measurable progress.
struct ProcessingStatusView: View {
    let title: Text
    let message: Text
    let accessibilityLabel: Text

    var body: some View {
        VStack(spacing: 12) {
            title
                .font(AppFont.title1Bold)
                .accessibilityAddTraits(.isHeader)
            message
                .font(AppFont.title1)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            ProgressView()
                .controlSize(.large)
                .padding(.top, 2)
                .accessibilityLabel(accessibilityLabel)
        }
        .foregroundStyle(AppColor.primaryText)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.canvas.ignoresSafeArea())
    }
}
