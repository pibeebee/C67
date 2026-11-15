import SwiftUI

/// Full-screen trip ordering and completion states.
///
/// The message moves from the trip, to the weather, to live traffic, then stays on the last one
/// until the caller replaces this view with the result.
struct TripProcessingView: View {
    @State private var stage: TripProcessingStage
    private let advances: Bool
    private let messageOverride: String?
    private let isReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - stage: The first message to show.
    ///   - advances: Whether the messages move on by themselves. Previews pass false to hold one.
    init(stage: TripProcessingStage = .puttingTogether, advances: Bool = true, messageOverride: String? = nil, isReady: Bool = false) {
        _stage = State(initialValue: stage)
        self.advances = advances
        self.messageOverride = messageOverride
        self.isReady = isReady
    }

    var body: some View {
        Group {
            if isReady {
                Text("\(QuestionTitle.highlight("All set!")) Here’s come your \(QuestionTitle.highlight("itinerary!"))")
                    .font(AppFont.title1Bold)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("tripProcessingReady")
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.canvas.ignoresSafeArea())
            } else {
                VStack(spacing: 8) {
                    Text("Hang on tight!")
                        .font(AppFont.title1Bold)
                        .accessibilityAddTraits(.isHeader)
                    (messageOverride.map { Text($0) } ?? Self.message(for: stage))
                        .font(AppFont.title1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColor.secondaryText)
                        .padding(.top, 24)
                        .accessibilityLabel("Building your itinerary")
                }
                .foregroundStyle(AppColor.primaryText)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.canvas.ignoresSafeArea())
            }
        }
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
            Text("Putting your \(QuestionTitle.highlight("trip"))\ntogether…")
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

    #Preview("Itinerary ready") {
        TripProcessingView(advances: false, isReady: true)
    }

    #Preview("Animated · Dark") {
        TripProcessingView()
            .preferredColorScheme(.dark)
    }
#endif
