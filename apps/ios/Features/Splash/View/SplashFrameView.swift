import SwiftUI

/// Draws one moment of the Travelant splash animation.
///
/// `SplashView` feeds it frames over time; previews and tests can show any single frame.
struct SplashFrameView: View {
    let frame: SplashTimeline.Frame

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: AppColor.splashTop, location: 0),
                    .init(color: AppColor.splashMiddle, location: 0.45),
                    .init(color: AppColor.splashBottom, location: 1),
                ],
                startPoint: UnitPoint(x: 0.3, y: 0),
                endPoint: UnitPoint(x: 0.7, y: 1)
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                lockup
                tagline
                    .padding(.top, 10)
            }
            .offset(y: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Travelant. \(SplashTimeline.tagline)")
    }

    /// The mark with the wordmark under it, in one box so the relay ball can travel between them.
    private var lockup: some View {
        ZStack(alignment: .topLeading) {
            if let ball = frame.relayBall, ball.isBehindMark {
                relayBall(ball)
            }
            mark
                .offset(x: SplashTimeline.markOrigin.x, y: SplashTimeline.markOrigin.y)
            wordmark
            if let ball = frame.relayBall, !ball.isBehindMark {
                relayBall(ball)
            }
            landingRipple
        }
        .frame(
            width: SplashTimeline.lockupSize.width,
            height: SplashTimeline.lockupSize.height,
            alignment: .topLeading
        )
    }

    private var mark: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0 ..< 2, id: \.self) { index in
                let antenna = TravelantMarkAssets.antennas[index]
                Image(antenna.name)
                    .resizable()
                    .frame(width: antenna.frame.width, height: antenna.frame.height)
                    .scaleEffect(max(frame.antennaScale[index], 0.01), anchor: antenna.anchor)
                    .rotationEffect(.degrees(frame.antennaAngle[index]), anchor: antenna.anchor)
                    .opacity(frame.antennaScale[index] > 0 ? 1 : 0)
                    .position(antenna.center)
            }

            route

            ForEach(0 ..< frame.pulseProgress.count, id: \.self) { index in
                let pulse = frame.pulseProgress[index]
                Circle()
                    .stroke(.white.opacity(0.8 * (1 - pulse)), lineWidth: 1.5)
                    .frame(width: rippleDiameter(pulse), height: rippleDiameter(pulse))
                    .position(TravelantMarkGeometry.ringCenter)
                    .opacity(pulse > 0 && pulse < 1 ? 1 : 0)
            }

            TravelantBall(diameter: frame.ballDiameter)
                .scaleEffect(max(frame.penScale, 0.01))
                .opacity(frame.penScale > 0 ? 1 : 0)
                .position(frame.ballCenter)
        }
        .frame(width: TravelantMarkGeometry.designSize.width, height: TravelantMarkGeometry.designSize.height)
    }

    /// The Figma route export, revealed along the pin's center line as the ball draws it.
    private var route: some View {
        Image(TravelantMarkAssets.route.name)
            .resizable()
            .frame(width: TravelantMarkAssets.route.frame.width, height: TravelantMarkAssets.route.frame.height)
            .position(TravelantMarkAssets.route.center)
            .frame(width: TravelantMarkGeometry.designSize.width, height: TravelantMarkGeometry.designSize.height)
            .mask {
                TravelantPinShape()
                    .trim(from: 0, to: TravelantMarkGeometry.revealTrimEnd(for: frame.drawProgress))
                    .stroke(style: StrokeStyle(lineWidth: TravelantMarkAssets.revealWidth, lineCap: .butt, lineJoin: .round))
            }
            .opacity(frame.drawProgress > 0 ? 1 : 0)
    }

    private func rippleDiameter(_ pulse: Double) -> CGFloat {
        TravelantMarkGeometry.ballDiameter * (1.2 + 0.45 * CGFloat(pulse))
    }

    /// The italic wordmark: each letter springs up from its baseline as the relay ball passes,
    /// and the ball pulls the "t" crossbar out to where it parks.
    private var wordmark: some View {
        ZStack(alignment: .topLeading) {
            ForEach(TravelantWordmarkGeometry.glyphs.indices, id: \.self) { index in
                let pop = frame.letterPop[index]
                TravelantWordmarkLetter(index: index)
                    .fill(.white)
                    .scaleEffect(
                        x: 0.7 + 0.3 * CGFloat(min(pop, 1)),
                        y: CGFloat(max(pop, 0.001)),
                        anchor: lockupAnchor(TravelantWordmarkGeometry.letterPivots[index])
                    )
                    .opacity(frame.letterOpacity[index])
            }

            TravelantWordmarkCrossbar()
                .trim(from: 0, to: frame.crossbarProgress)
                .stroke(.white, style: StrokeStyle(lineWidth: TravelantWordmarkGeometry.crossbarWidth, lineCap: .round))
                .opacity(frame.crossbarProgress > 0 ? 1 : 0)
        }
        .frame(width: SplashTimeline.lockupSize.width, height: SplashTimeline.lockupSize.height)
        .compositingGroup()
        .shadow(color: AppColor.splashShadow.opacity(0.28), radius: 9, y: 6)
    }

    private func relayBall(_ ball: SplashTimeline.RelayBall) -> some View {
        TravelantBall(diameter: ball.diameter)
            .position(ball.center)
    }

    /// The ring that spreads from the ball as it parks at the end of the "t".
    private var landingRipple: some View {
        let spread = SplashTimeline.easeOut(frame.landingRipple)
        let diameter = TravelantWordmarkGeometry.ballDiameter * (1 + 2.4 * CGFloat(spread))
        return Circle()
            .stroke(.white.opacity(0.9 * (1 - spread)), lineWidth: 1.6 * (1 - 0.6 * CGFloat(spread)))
            .frame(width: diameter, height: diameter)
            .position(TravelantWordmarkGeometry.ballCenter)
            .opacity(frame.landingRipple > 0 && frame.landingRipple < 1 ? 1 : 0)
    }

    private func lockupAnchor(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: point.x / SplashTimeline.lockupSize.width, y: point.y / SplashTimeline.lockupSize.height)
    }

    private var tagline: some View {
        HStack(spacing: 8) {
            ForEach(Array(SplashTimeline.taglineWords.enumerated()), id: \.offset) { index, word in
                let progress = frame.wordProgress[index]
                Text(verbatim: word)
                    .opacity(progress)
                    .blur(radius: 6 * (1 - progress))
                    .offset(y: 6 * (1 - progress))
            }
        }
        .font(AppFont.brandTagline)
        .foregroundStyle(AppColor.splashTagline)
    }
}

#if DEBUG
    #Preview("1 · Pen appears (0.5 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 0.5))
    }

    #Preview("2 · Drawing the pin (1.2 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 1.2))
    }

    #Preview("3 · Pin almost closed (1.8 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 1.8))
    }

    #Preview("4 · Ball hops to center (2.3 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 2.3))
    }

    #Preview("5 · First pulse (2.75 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 2.75))
    }

    #Preview("6 · Antennae (3.6 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 3.6))
    }

    #Preview("7 · Antennae wave (4.2 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 4.2))
    }

    #Preview("8 · Relay ball drops from the pin (4.8 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 4.8))
    }

    #Preview("9 · Letters spring up as it rolls (5.5 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 5.5))
    }

    #Preview("10 · Ball pulls the t crossbar out (6.2 s)") {
        SplashFrameView(frame: SplashTimeline.frame(at: 6.2))
    }

    #Preview("11 · Final") {
        SplashFrameView(frame: SplashTimeline.finalFrame)
    }

    #Preview("11 · Final · Dark + large text") {
        SplashFrameView(frame: SplashTimeline.finalFrame)
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility2)
    }
#endif
