import SwiftUI

struct RecommendationsProcessingView: View {
    var body: some View {
        ProcessingStatusView(
            title: Text("We’ve got you."),
            message: Text("Searching for places for your \(QuestionTitle.highlight("trip"))…"),
            accessibilityLabel: Text("Finding recommendations")
        )
        .accessibilityIdentifier("recommendationsProcessing")
    }
}

#Preview("PREFERENCES PROCESSING 1 · Light") {
    RecommendationsProcessingView().preferredColorScheme(.light)
}

#Preview("PREFERENCES PROCESSING 1 · Dark") {
    RecommendationsProcessingView().preferredColorScheme(.dark)
}
