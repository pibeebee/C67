import SwiftUI

/// Sketch HI-FI `PREFERENCES PROCESSING 2`, `3` and `4`: "I’ve got you." while the itinerary is built.
///
/// The message moves from the trip, to the weather, to live traffic, then stays on the last one
/// until the caller replaces this view with the result.
struct TripProcessingView: View {
    @State private var stage: TripProcessingStage
    private let advances: Bool
    private let messageOverride: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - stage: The first message to show.
    ///   - advances: Whether the messages move on by themselves. Previews pass false to hold one.
    init(stage: TripProcessingStage = .puttingTogether, advances: Bool = true, messageOverride: String? = nil) {
        _stage = State(initialValue: stage)
        self.advances = advances
        self.messageOverride = messageOverride
    }

    var body: some View {
        ProcessingStatusView(
            title: Text("I’ve got you."),
            message: messageOverride.map { Text($0) } ?? Self.message(for: stage),
            accessibilityLabel: Text("Building your itinerary")
        )
        .accessibilityIdentifier("tripProcessing")
        .task {
            guard advances else { return }
            while let next = stage.next {
                try? await Task.sleep(for: TripProcessingStage.interval)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    stage = next
                }
            }
        }
    }

    static func message(for stage: TripProcessingStage) -> Text {
        switch stage {
        case .puttingTogether:
            Text("Putting your \(QuestionTitle.highlight("trip")) together…")
        case .checkingWeather:
            Text("Checking the \(QuestionTitle.highlight("weather")) forecast…")
        case .scanningTraffic:
            Text("Scanning \(QuestionTitle.highlight("live traffic")) & \(QuestionTitle.highlight("routes"))…")
        }
    }
}

#if DEBUG
    #Preview("PREFERENCES PROCESSING 2") {
        TripProcessingView(stage: .puttingTogether, advances: false)
    }

    #Preview("PREFERENCES PROCESSING 3") {
        TripProcessingView(stage: .checkingWeather, advances: false)
    }

    #Preview("PREFERENCES PROCESSING 4") {
        TripProcessingView(stage: .scanningTraffic, advances: false)
    }

    #Preview("Animated · Dark") {
        TripProcessingView()
            .preferredColorScheme(.dark)
    }
#endif
