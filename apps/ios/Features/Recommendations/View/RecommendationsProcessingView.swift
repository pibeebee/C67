import SwiftUI

struct RecommendationsProcessingView: View {
    var body: some View {
        ProcessingStatusView(
            title: Text("We’ve got you."),
            message: Text("Searching for places for your \(QuestionTitle.highlight("trip"))…")
        ) {
            RecommendationProcessingIllustration()
        }
        .accessibilityIdentifier("recommendationsProcessing")
    }
}

/// Brief hand-off after the first search succeeds: the line settles in, holds, then gives way to the list.
struct RecommendationsFoundView: View {
    var body: some View {
        HandOffMessage(text: Text("Fantastic! Here’s what we \(QuestionTitle.highlight("found")) for you"))
            .accessibilityIdentifier("recommendationsFound")
    }
}

/// A one-line celebration between a wait and its result. The line settles in out of a soft blur;
/// with `leavesAfter`, it lifts away and fades before the caller swaps it out. Reduce Motion only fades.
struct HandOffMessage: View {
    let text: Text
    var leavesAfter: Duration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var leaving = false

    var body: some View {
        text
            .font(AppFont.title1Bold)
            .foregroundStyle(AppColor.primaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            .scaleEffect(reduceMotion ? 1 : (leaving ? 1.04 : settled ? 1 : 0.94))
            .offset(y: reduceMotion ? 0 : (leaving ? -16 : settled ? 0 : 14))
            .blur(radius: reduceMotion || (settled && !leaving) ? 0 : 8)
            .opacity(settled && !leaving ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.canvas.ignoresSafeArea())
            .accessibilityAddTraits(.isHeader)
            // A short, non-blocking moment: taps reach whatever it is revealing.
            .allowsHitTesting(false)
            .task {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.2)) { settled = true }
                guard let leavesAfter else { return }
                try? await Task.sleep(for: leavesAfter)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4)) { leaving = true }
            }
    }
}

#Preview("Recommendations found") {
    RecommendationsFoundView()
}

#Preview("PREFERENCES PROCESSING 1 · Light") {
    RecommendationsProcessingView().preferredColorScheme(.light)
}

#Preview("PREFERENCES PROCESSING 1 · Dark") {
    RecommendationsProcessingView().preferredColorScheme(.dark)
}
