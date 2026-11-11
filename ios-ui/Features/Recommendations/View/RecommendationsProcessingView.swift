import SwiftUI

struct RecommendationsProcessingView: View {
    var body: some View {
        ProcessingStatusView(
            title: Text("Hang tight!"),
            message: Text("Curating the \(QuestionTitle.highlight("best spots")) for your trip…"),
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
