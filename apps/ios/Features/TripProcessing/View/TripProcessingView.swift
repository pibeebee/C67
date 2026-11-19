import SwiftUI
import C67Domain

/// Full-screen trip ordering and completion states.
///
/// The message moves from the trip, to the weather, to live traffic, then stays on the last one
/// until the caller replaces this view with the result.
struct TripProcessingView: View {
    @State private var stage: TripProcessingStage
    private let advances: Bool
    private let messageOverride: String?
    private let activity: PlanningActivity?
    private let isReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - stage: The first message to show.
    ///   - advances: Whether the messages move on by themselves. Previews pass false to hold one.
    init(stage: TripProcessingStage = .puttingTogether, advances: Bool = true, messageOverride: String? = nil, activity: PlanningActivity? = nil, isReady: Bool = false) {
        _stage = State(initialValue: stage)
        self.advances = advances
        self.messageOverride = messageOverride
        self.activity = activity
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
                ProcessingStatusView(
                    title: Text("Hang on tight!"),
                    message: activity.map(Self.message(for:)) ?? messageOverride.map { Text($0) } ?? Self.message(for: stage),
                    spacing: 24
                ) {
                    TripRouteIllustration(activity: activity, reduceMotion: reduceMotion)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: activity)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: activity)
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

    private static func message(for activity: PlanningActivity) -> Text {
        switch activity {
        case .weather: Text("Checking the \(QuestionTitle.highlight("weather")) and daylight…")
        case .luna: Text("Tailoring each stop to your \(QuestionTitle.highlight("interests"))…")
        case .onDeviceAdvice: Text("Working out \(QuestionTitle.highlight("visit suggestions")) on this device…")
        case .openingHours: Text("Matching stops to \(QuestionTitle.highlight("opening hours"))…")
        case .travelTimes: Text("Comparing \(QuestionTitle.highlight("travel times"))…")
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

private struct TripRouteIllustration: View, @MainActor Animatable {
    @Environment(\.colorScheme) private var colorScheme

    let reduceMotion: Bool
    private var weather: Double
    private var advice: Double
    private var hours: Double
    private var routes: Double
    private let stops = [CGPoint(x: 48, y: 162), CGPoint(x: 107, y: 94), CGPoint(x: 192, y: 116), CGPoint(x: 267, y: 62)]
    private let cycle = 5.5
    private let cardSize = CGSize(width: 320, height: 218)
    private let timelinePinY = 188.0

    init(activity: PlanningActivity?, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        weather = activity == .weather ? 1 : 0
        advice = activity == .luna || activity == .onDeviceAdvice ? 1 : 0
        hours = activity == .openingHours ? 1 : 0
        routes = activity == .travelTimes ? 1 : 0
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(weather, advice), .init(hours, routes)) }
        set { (weather, advice, hours, routes) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }

    private var timeline: Double { min(1, weather + advice + hours) }
    private var panelTop: Double { cardSize.height - timeline * 94 }
    private var mapOffset: Double { -38 * timeline }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tick in
            let elapsed = tick.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: cycle) / cycle
            Canvas { context, size in
                var scene = context
                scene.scaleBy(x: size.width / cardSize.width, y: size.height / cardSize.height)
                let surface = colorScheme == .dark
                    ? Color(red: 0.09, green: 0.13, blue: 0.20)
                    : AppColor.surface
                scene.fill(Path(CGRect(origin: .zero, size: cardSize)), with: .color(surface))

                // Reveal the timeline by moving the map upward without stretching it.
                var map = scene
                map.clip(to: Path(CGRect(x: 0, y: 0, width: cardSize.width, height: panelTop)))
                map.translateBy(x: 0, y: mapOffset)
                drawMap(in: map)
                drawRoute(in: map, phase: phase)
                drawTimeline(in: scene, phase: phase)
                drawPins(in: scene)
            }
        }
        .aspectRatio(cardSize.width / cardSize.height, contentMode: .fit)
        .frame(maxWidth: cardSize.width, maxHeight: cardSize.height)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(AppColor.primaryText.opacity(0.09), lineWidth: 1)
        }
    }

    private func drawMap(in context: GraphicsContext) {
        let dark = colorScheme == .dark
        let land = dark ? Color(red: 0.13, green: 0.16, blue: 0.20) : Color(red: 0.95, green: 0.943, blue: 0.923)
        let block = dark ? Color.white.opacity(0.045) : Color(red: 0.91, green: 0.90, blue: 0.87)
        let park = dark ? Color(red: 0.18, green: 0.26, blue: 0.23) : Color(red: 0.85, green: 0.89, blue: 0.82)
        let road = dark ? Color.white.opacity(0.17) : Color.white.opacity(0.94)
        let water = dark ? Color(red: 0.14, green: 0.25, blue: 0.35) : Color(red: 0.83, green: 0.90, blue: 0.94)

        context.fill(Path(CGRect(origin: .zero, size: cardSize)), with: .color(land))
        // Hand-drawn blocks keep the route readable at this illustration's small size.
        for outline in [
            [CGPoint(x: 8, y: 64), CGPoint(x: 29, y: 37), CGPoint(x: 77, y: 39), CGPoint(x: 58, y: 67)],
            [CGPoint(x: 102, y: 51), CGPoint(x: 122, y: 31), CGPoint(x: 155, y: 32), CGPoint(x: 150, y: 63)],
            [CGPoint(x: 166, y: 40), CGPoint(x: 190, y: 43), CGPoint(x: 199, y: 74), CGPoint(x: 167, y: 72)],
            [CGPoint(x: 243, y: 85), CGPoint(x: 266, y: 89), CGPoint(x: 281, y: 110), CGPoint(x: 231, y: 107)],
            [CGPoint(x: 101, y: 133), CGPoint(x: 126, y: 128), CGPoint(x: 147, y: 160), CGPoint(x: 118, y: 170)],
        ] {
            context.fill(Path { $0.addLines(outline); $0.closeSubpath() }, with: .color(block))
        }

        let green = Path { path in
            path.move(to: CGPoint(x: -4, y: 95))
            path.addQuadCurve(to: CGPoint(x: 48, y: 94), control: CGPoint(x: 23, y: 76))
            path.addQuadCurve(to: CGPoint(x: 41, y: 124), control: CGPoint(x: 64, y: 108))
            path.addQuadCurve(to: CGPoint(x: -4, y: 139), control: CGPoint(x: 18, y: 139))
            path.closeSubpath()
            path.move(to: CGPoint(x: 207, y: 28))
            path.addQuadCurve(to: CGPoint(x: 251, y: 26), control: CGPoint(x: 229, y: 8))
            path.addQuadCurve(to: CGPoint(x: 242, y: 50), control: CGPoint(x: 256, y: 44))
            path.addQuadCurve(to: CGPoint(x: 207, y: 28), control: CGPoint(x: 214, y: 51))
            path.closeSubpath()
        }
        context.fill(green, with: .color(park))

        let waterfront = Path { path in
            path.move(to: CGPoint(x: 308, y: -8))
            path.addCurve(to: CGPoint(x: 278, y: 144), control1: CGPoint(x: 288, y: 52), control2: CGPoint(x: 328, y: 104))
            path.addCurve(to: CGPoint(x: 93, y: 223), control1: CGPoint(x: 230, y: 186), control2: CGPoint(x: 161, y: 162))
            path.addLine(to: CGPoint(x: 330, y: 227))
            path.addLine(to: CGPoint(x: 330, y: -8))
            path.closeSubpath()
        }
        context.fill(waterfront, with: .color(water))

        let avenues = Path { path in
            path.move(to: CGPoint(x: -12, y: 176))
            path.addQuadCurve(to: stops[0], control: CGPoint(x: 24, y: 181))
            path.addPath(mainRoute)
            path.move(to: stops[3])
            path.addLine(to: CGPoint(x: 284, y: -8))
            path.move(to: CGPoint(x: -8, y: 47))
            path.addQuadCurve(to: CGPoint(x: 300, y: 75), control: CGPoint(x: 137, y: 8))
            path.move(to: CGPoint(x: 160, y: -10))
            path.addCurve(to: CGPoint(x: 141, y: 192), control1: CGPoint(x: 135, y: 37), control2: CGPoint(x: 199, y: 137))
        }
        context.stroke(avenues, with: .color(road), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))

        let lanes = Path { path in
            path.addLines([CGPoint(x: 46, y: -4), CGPoint(x: 29, y: 37), CGPoint(x: -8, y: 70)])
            path.addLines([CGPoint(x: 91, y: -4), CGPoint(x: 89, y: 49), CGPoint(x: 74, y: 80), CGPoint(x: 49, y: 101)])
            path.addLines([CGPoint(x: 116, y: 22), CGPoint(x: 115, y: 62), stops[1], CGPoint(x: 87, y: 113)])
            path.addLines([CGPoint(x: 39, y: 129), CGPoint(x: 82, y: 126), CGPoint(x: 125, y: 130), CGPoint(x: 144, y: 151)])
            path.addLines([CGPoint(x: 8, y: 147), CGPoint(x: 27, y: 148), stops[0], CGPoint(x: 64, y: 191)])
            path.addLines([CGPoint(x: 208, y: 42), CGPoint(x: 211, y: 76), CGPoint(x: 240, y: 86), CGPoint(x: 290, y: 88)])
            path.addLines([CGPoint(x: 175, y: 156), CGPoint(x: 202, y: 147), CGPoint(x: 244, y: 144), CGPoint(x: 280, y: 126)])
        }
        context.stroke(lanes, with: .color(road.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private var mainRoute: Path {
        Path { path in
            path.move(to: stops[0])
            path.addCurve(to: stops[1], control1: CGPoint(x: 77, y: 155), control2: CGPoint(x: 72, y: 101))
            path.addCurve(to: stops[2], control1: CGPoint(x: 133, y: 89), control2: CGPoint(x: 153, y: 124))
            path.addCurve(to: stops[3], control1: CGPoint(x: 229, y: 109), control2: CGPoint(x: 228, y: 78))
        }
    }

    private func drawRoute(in context: GraphicsContext, phase: Double) {
        var routeLayer = context
        routeLayer.opacity = 1 - timeline * 0.89
        if routes > 0 {
            let alternative = Path { path in
                path.move(to: stops[0])
                path.addQuadCurve(to: CGPoint(x: 110, y: 159), control: CGPoint(x: 78, y: 170))
                path.addCurve(to: stops[3], control1: CGPoint(x: 203, y: 137), control2: CGPoint(x: 278, y: 177))
            }
            routeLayer.stroke(alternative, with: .color(AppColor.accent.opacity(routes * 0.45)),
                              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
        }
        let route = mainRoute
        routeLayer.stroke(route, with: .color(whiteOutline), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        routeLayer.stroke(route, with: .color(AppColor.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        if !reduceMotion {
            let head = phase * 1.22 - 0.11
            let tail = max(0, head - 0.11)
            let end = min(1, head)
            if tail < end {
                routeLayer.stroke(route.trimmedPath(from: tail, to: end), with: .color(Color.white.opacity(0.72)),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func drawTimeline(in context: GraphicsContext, phase: Double) {
        guard timeline > 0 else { return }
        var divider = Path()
        divider.move(to: CGPoint(x: 0, y: panelTop))
        divider.addLine(to: CGPoint(x: cardSize.width, y: panelTop))
        context.stroke(divider, with: .color(AppColor.accent.opacity(0.12 * timeline)), lineWidth: 1)

        var strip = context
        strip.opacity = timeline
        strip.clip(to: Path(CGRect(x: 0, y: panelTop, width: cardSize.width, height: cardSize.height - panelTop)))
        strip.translateBy(x: 0, y: (1 - timeline) * 24)

        var rail = Path()
        rail.move(to: CGPoint(x: 26, y: timelinePinY))
        rail.addLine(to: CGPoint(x: 294, y: timelinePinY))
        strip.stroke(rail, with: .color(AppColor.accent.opacity(0.18)), lineWidth: 1.5)

        if weather > 0 {
            var sky = strip
            sky.opacity *= weather / timeline
            var daylight = Path()
            daylight.move(to: CGPoint(x: 44, y: 175))
            daylight.addQuadCurve(to: CGPoint(x: 276, y: 175), control: CGPoint(x: 160, y: 146))
            sky.stroke(daylight, with: .color(.orange.opacity(0.64)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            let sun = 0.5 - cos(phase * 2 * .pi) * 0.4
            symbol("sun.max.fill", color: .orange, at: CGPoint(x: 44 + 232 * sun, y: 175 - 58 * sun * (1 - sun)), in: sky, size: 11)
            symbol("sunrise", color: .orange, at: CGPoint(x: 44, y: 143), in: sky, size: 19)
            symbol("cloud.rain", color: AppColor.accent, at: CGPoint(x: 160, y: 143), in: sky, size: 19)
            symbol("sunset", color: .orange, at: CGPoint(x: 276, y: 143), in: sky, size: 19)
        }
        if hours > 0 {
            var windows = strip
            windows.opacity *= hours / timeline
            for (index, width) in [35.0, 49.0, 38.0, 54.0].enumerated() {
                let x = timelineX(index)
                let emphasis = reduceMotion ? 0.65 : 0.65 + 0.35 * cos((phase - Double(index) / Double(stops.count)) * 2 * .pi)
                let window = Path(roundedRect: CGRect(x: x - width / 2, y: 175, width: width, height: 22), cornerRadius: 5)
                windows.fill(window, with: .color(.teal.opacity(0.09 + 0.09 * emphasis)))
                windows.stroke(window, with: .color(.teal.opacity(0.24 + 0.20 * emphasis)), lineWidth: 1)
            }
            symbol("clock", color: .teal, at: CGPoint(x: 160, y: 152), in: windows, size: 17)
        }
        if advice > 0 {
            var suggestions = strip
            suggestions.opacity *= advice / timeline
            var connections = Path()
            for index in stops.indices.dropLast() {
                let start = timelineX(index)
                let end = timelineX(index + 1)
                connections.move(to: CGPoint(x: start + 10, y: timelinePinY))
                connections.addLine(to: CGPoint(x: end - 10, y: timelinePinY))
            }
            suggestions.stroke(connections, with: .color(AppColor.accent.opacity(0.50)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5], dashPhase: -phase * 28))
            symbol("list.bullet", color: AppColor.accent, at: CGPoint(x: 160, y: 152), in: suggestions, size: 17)
        }
    }

    private func drawPins(in context: GraphicsContext) {
        for (index, point) in stops.enumerated() {
            let x = point.x + (timelineX(index) - point.x) * timeline
            let y = point.y + (timelinePinY - point.y) * timeline
            var pin = context
            pin.translateBy(x: x, y: y)
            if timeline > 0 {
                let node = Path(ellipseIn: CGRect(x: -4.5, y: -4.5, width: 9, height: 9))
                pin.fill(node, with: .color(AppColor.accent.opacity(timeline)))
                pin.stroke(node, with: .color(whiteOutline.opacity(timeline)), lineWidth: 1.5)
            }
            pin.opacity = 1 - timeline
            pin.scaleBy(x: 1 - timeline * 0.28, y: 1 - timeline * 0.28)
            let marker = Path { path in
                path.move(to: .zero)
                path.addQuadCurve(to: CGPoint(x: -10, y: -15), control: CGPoint(x: -10, y: -8))
                path.addQuadCurve(to: CGPoint(x: 10, y: -15), control: CGPoint(x: 0, y: -35))
                path.addQuadCurve(to: .zero, control: CGPoint(x: 10, y: -8))
                path.closeSubpath()
            }
            pin.fill(marker, with: .color(AppColor.accent))
            pin.stroke(marker, with: .color(whiteOutline), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            pin.fill(Path(ellipseIn: CGRect(x: -3, y: -19, width: 6, height: 6)), with: .color(.white))
        }
    }

    private func timelineX(_ index: Int) -> Double { 42 + Double(index) * 78 }

    private var whiteOutline: Color { colorScheme == .dark ? .black.opacity(0.72) : .white }

    private func symbol(_ name: String, color: Color, at point: CGPoint, in context: GraphicsContext, size: Double = 18) {
        context.draw(Text(Image(systemName: name)).font(.system(size: size, weight: .semibold)).foregroundColor(color), at: point)
    }
}

#if DEBUG
    struct TripProcessingActivityPreview: View {
        @State private var activity: PlanningActivity?

        var body: some View {
            TripProcessingView(advances: false, activity: activity)
                .task {
                    let scenes: [PlanningActivity] = [.weather, .luna, .openingHours, .travelTimes]
                    var index = 0
                    while !Task.isCancelled {
                        guard (try? await Task.sleep(for: .seconds(2.8))) != nil, !Task.isCancelled else { return }
                        activity = scenes[index]
                        index = (index + 1) % scenes.count
                    }
                }
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
