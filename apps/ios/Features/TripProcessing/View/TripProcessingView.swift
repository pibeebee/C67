import SwiftUI
import C67Domain

/// Full-screen trip ordering and completion states.
///
/// It opens on the planner's own status line (for example "Checking candidate schedules…"), then
/// cycles the three Sketch scenes on a timer — routes, putting it together, forecast — regardless
/// of what the planner is doing, until the caller replaces this view with the result.
struct TripProcessingView: View {
    @State private var stage: TripProcessingStage
    @State private var opening: String?
    @State private var rotation: Scene?
    private let advances: Bool
    private let messageOverride: String?
    private let isReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long each line stays on screen before the next one.
    static let sceneInterval: Duration = .seconds(2.8)
    /// The order the scenes cycle in once the opening line has been shown.
    static let sceneCycle: [Scene] = [.routes, .together, .forecast]

    /// - Parameters:
    ///   - stage: The scene to hold when there is no opening line and the view doesn't advance.
    ///   - advances: Whether the scenes cycle by themselves. Previews pass false to hold one.
    ///   - messageOverride: The planner's status line shown first, before the scenes start cycling.
    init(stage: TripProcessingStage = .puttingTogether, advances: Bool = true, messageOverride: String? = nil, isReady: Bool = false) {
        _stage = State(initialValue: stage)
        _opening = State(initialValue: messageOverride)
        self.advances = advances
        self.messageOverride = messageOverride
        self.isReady = isReady
    }

    private var scene: Scene? { rotation ?? (opening == nil ? Scene(stage) : nil) }

    private var message: Text {
        if let rotation { return Self.message(for: rotation) }
        if let opening { return Self.message(forStatus: opening) }
        return Self.message(for: Scene(stage))
    }

    var body: some View {
        Group {
            if isReady {
                // Same hand-off as "Here's what we found"; it lifts away just before the itinerary appears.
                HandOffMessage(text: Text("\(QuestionTitle.highlight("All set!")) Here’s come your \(QuestionTitle.highlight("itinerary"))"),
                               leavesAfter: .seconds(1.25))
                    .accessibilityIdentifier("tripProcessingReady")
            } else {
                TripPlanningWaitLayout(message: message, raining: scene == .forecast)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: scene)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: opening)
            }
        }
        .accessibilityIdentifier("tripProcessing")
        .onChange(of: messageOverride) { _, status in
            // Only the first status line opens the sequence; later planner updates don't interrupt it.
            if opening == nil, rotation == nil, let status { opening = status }
        }
        .task {
            guard advances else { return }
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sceneInterval)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    rotation = Self.sceneCycle[index % Self.sceneCycle.count]
                }
                index += 1
            }
        }
    }

    /// The planner's status line, with its key word highlighted like the scene lines.
    static func message(forStatus status: String) -> Text {
        switch status {
        case "Checking candidate schedules…": Text("Checking \(QuestionTitle.highlight("candidate")) schedules…")
        case "Preparing your itinerary…": Text("Preparing your \(QuestionTitle.highlight("itinerary"))…")
        case "Checking driving times…": Text("Checking \(QuestionTitle.highlight("driving times"))…")
        default: Text(status)
        }
    }

    /// The three scenes from Sketch HI-FI `PREFERENCES PROCESSING 2`: forecast (with rain), routes,
    /// then putting the itinerary together.
    enum Scene: Equatable {
        case forecast, routes, together

        init(_ stage: TripProcessingStage) {
            switch stage {
            case .checkingWeather: self = .forecast
            case .scanningTraffic: self = .routes
            case .puttingTogether: self = .together
            }
        }
    }

    static func message(for scene: Scene) -> Text {
        switch scene {
        case .forecast: Text("Checking the \(QuestionTitle.highlight("forecast")) so you don’t get rained on…")
        case .routes: Text("Finding the \(QuestionTitle.highlight("smoothest routes")) between spots…")
        case .together: Text("Putting your \(QuestionTitle.highlight("itinerary")) together…")
        }
    }

    static func message(for stage: TripProcessingStage) -> Text { message(for: Scene(stage)) }
}

/// Sketch HI-FI `PREFERENCES PROCESSING 2`, measured on the 402 × 874 artboard: the drive scene
/// bleeds past both edges with its top at 91 pt, then a centred title at 424 pt and the
/// status at 489 pt. Shorter screens scale the vertical positions down; actions sit in the caller's inset.
private struct TripPlanningWaitLayout: View {
    let message: Text
    let raining: Bool

    private static let artboardHeight = 874.0

    var body: some View {
        GeometryReader { proxy in
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let scale = min(1, fullHeight / Self.artboardHeight)
            let sceneWidth = proxy.size.width * 386.75 / 402
            VStack(alignment: .leading, spacing: 0) {
                // The scene bleeds past the margins without widening the centred text column.
                Color.clear
                    .frame(height: sceneWidth * 185 / 364)
                    .overlay(alignment: .leading) {
                        TripPlanningDriveIllustration(raining: raining)
                            .frame(width: sceneWidth, height: sceneWidth * 185 / 364)
                            .offset(x: -3 - 20)
                    }
                    .padding(.top, 91 * scale - proxy.safeAreaInsets.top)
                Text("Hang on tight!")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(AppColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, max(16, (424 - 91) * scale - sceneWidth * 185 / 364))
                message
                    .contentTransition(.opacity)
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.primaryText)
                    .frame(maxWidth: 306)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24 * scale)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.canvas.ignoresSafeArea())
    }
}

#if DEBUG
    /// The production sequence: the planner's status line, then the scenes on a timer.
    struct TripProcessingActivityPreview: View {
        var body: some View {
            TripProcessingView(messageOverride: "Checking candidate schedules…")
        }
    }

    #Preview("Planning activities") {
        TripProcessingActivityPreview()
    }

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
