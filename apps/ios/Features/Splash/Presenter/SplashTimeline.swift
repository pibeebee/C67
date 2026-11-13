import CoreGraphics
import Foundation

/// Timing of the Travelant splash animation.
///
/// The mark follows the brand video `Travelant-Splash-iPhone17.mp4` and Figma "✅ FINAL · 08 · GPS
/// Trail + Lambaian", measured frame by frame (30 fps): the ball traces the route, hops into the
/// center, pulses twice, and the antennae grow, then wave. The wordmark follows option 1, "Ball
/// relay": a small ball slips out from behind the pin, bounces down and rolls along the italic
/// wordmark, each letter springs up as it passes, and the ball pulls the "t" crossbar out and
/// parks at its end. The tagline fades in last.
///
/// `frame(at:)` is a pure function of elapsed time, so any moment can be previewed or tested.
enum SplashTimeline {
    static let tagline = "Your trip planner bestie"
    static let taglineWords = tagline.split(separator: " ").map(String.init)

    // MARK: Lockup

    /// The mark and the wordmark share one box, so the relay ball can travel between them.
    static let lockupSize = CGSize(width: 240, height: 262)
    /// Top-left of the `TravelantMarkGeometry` design box inside the lockup.
    static let markOrigin = CGPoint(x: 40, y: 0)

    // MARK: Mark

    static let penAppear: ClosedRange<Double> = 0.33 ... 0.55
    static let draw: ClosedRange<Double> = 0.6 ... 2.1
    /// How far along the route the ball is at each moment, sampled from the video every 0.1 s
    /// (time, fraction of the route's length). Nearly constant speed with short eases at both ends.
    static let drawKeyframes: [(time: Double, progress: Double)] = [
        (0.6, 0), (0.73, 0.06), (0.83, 0.12), (0.93, 0.19), (1.03, 0.26), (1.13, 0.36),
        (1.23, 0.44), (1.33, 0.54), (1.43, 0.62), (1.53, 0.71), (1.63, 0.79), (1.73, 0.85),
        (1.83, 0.92), (1.93, 0.96), (2.03, 0.99), (2.1, 1),
    ]
    /// Up, across and down into the center.
    static let hop: ClosedRange<Double> = 2.1 ... 2.57
    /// The ball grows from pen size, overshoots to about 42 pt, and settles at 40 pt.
    static let grow: ClosedRange<Double> = 2.1 ... 2.33
    static let pulses: [ClosedRange<Double>] = [2.63 ... 2.9, 2.93 ... 3.2]
    static let pulseScale = 0.12
    static let antennaGrowth: [ClosedRange<Double>] = [3.45 ... 3.75, 3.5 ... 3.8]
    static let antennaWave: [ClosedRange<Double>] = [4.07 ... 4.45, 4.14 ... 4.52]
    /// Peak swing of the wave; the leading antenna tips outward first.
    static let waveDegrees = 7.5

    /// Control points of the hop from the ring's end into the center.
    static let hopControls = (CGPoint(x: 108, y: 66), CGPoint(x: 80.8, y: 66))

    // MARK: Wordmark relay

    /// The relay ball grows in behind the pin's ball.
    static let relayAppear: ClosedRange<Double> = 4.5 ... 4.68
    /// It arcs from the pin down to the start of the baseline.
    static let relayArc: ClosedRange<Double> = 4.5 ... 4.95
    /// It rolls along the baseline in hops, the last one up onto the "t" crossbar.
    static let relayRoll: ClosedRange<Double> = 4.95 ... 6.05
    /// It slides along the crossbar, pulling the extension out, and shrinks to the wordmark ball.
    static let relaySlide: ClosedRange<Double> = 6.05 ... 6.35
    static let landingPulse: ClosedRange<Double> = 6.33 ... 6.65
    static let landingRippleSpread: ClosedRange<Double> = 6.35 ... 7.05
    /// While travelling the ball is 1.5 × the wordmark ball, so it reads at a glance.
    static let relayScale = 1.5
    static let landingPulseScale = 0.42
    static let arcHeight: CGFloat = 46
    /// Height of each hop along the baseline; the last one climbs to the crossbar.
    static let hopHeights: [CGFloat] = [16, 12, 8, 20]
    /// A letter starts to stand up just before the ball reaches its center.
    static let letterLead = 0.05
    static let letterDuration = 0.55
    static let letterBounce = 0.42

    static let taglineStart = 6.3
    static let wordStagger = 0.09
    static let wordDuration = 0.5
    /// When the last element has settled.
    static let duration = 7.1

    struct RelayBall: Equatable, Sendable {
        /// Center in lockup points.
        var center: CGPoint
        var diameter: CGFloat
        /// True while the ball slips out from behind the pin's ball.
        var isBehindMark: Bool
    }

    struct Frame: Equatable, Sendable {
        var penScale: Double
        var drawProgress: Double
        /// Center of the mark's ball in `TravelantMarkGeometry` design points.
        var ballCenter: CGPoint
        var ballDiameter: CGFloat
        /// Progress of each of the two pulses, 0…1.
        var pulseProgress: [Double]
        /// Growth of the leading and trailing antenna, 0…1 with overshoot.
        var antennaScale: [Double]
        /// Rotation of the leading and trailing antenna in degrees.
        var antennaAngle: [Double]
        /// The ball that carries the animation from the mark to the wordmark; nil before it appears.
        var relayBall: RelayBall?
        /// How far each letter stands up from its baseline: 0 flat, 1 upright, with spring overshoot.
        var letterPop: [Double]
        var letterOpacity: [Double]
        /// How much of the "t" crossbar extension the ball has pulled out, 0…1.
        var crossbarProgress: Double
        /// The ring that spreads from the ball as it parks, 0…1.
        var landingRipple: Double
        var wordProgress: [Double]
    }

    static func frame(at time: TimeInterval) -> Frame {
        let draw = drawProgress(at: time)
        let hop = progress(time, in: Self.hop)
        let pulses = pulses.map { progress(time, in: $0) }

        let center: CGPoint
        let diameter: CGFloat
        if time < Self.hop.lowerBound {
            center = TravelantMarkGeometry.point(at: draw)
            diameter = TravelantMarkGeometry.penDiameter
        } else {
            center = cubicPoint(
                TravelantMarkGeometry.point(at: 1), hopControls.0, hopControls.1, TravelantMarkGeometry.ringCenter,
                t: hop
            )
            let growth = CGFloat(easeOutBack(progress(time, in: grow)))
            let size = TravelantMarkGeometry.penDiameter
                + (TravelantMarkGeometry.ballDiameter - TravelantMarkGeometry.penDiameter) * growth
            let pulse = pulses.map { sin(.pi * $0) }.max() ?? 0
            diameter = size * CGFloat(1 + pulseScale * pulse)
        }

        let letters = letterPassTimes.map { pass in
            progress(time, in: (pass - letterLead) ... (pass - letterLead + letterDuration))
        }

        return Frame(
            penScale: easeOutBack(progress(time, in: penAppear)),
            drawProgress: draw,
            ballCenter: center,
            ballDiameter: diameter,
            pulseProgress: pulses,
            antennaScale: antennaGrowth.map { easeOutBack(progress(time, in: $0)) },
            antennaAngle: antennaWave.enumerated().map { index, range in
                let wave = progress(time, in: range)
                let direction: Double = index == 0 ? -1 : 1
                return direction * waveDegrees * sin(2 * .pi * wave)
            },
            relayBall: relayBall(at: time),
            letterPop: letters.map { spring($0, bounce: letterBounce) },
            letterOpacity: letters.map { min($0 * 5, 1) },
            crossbarProgress: easeOut(progress(time, in: relaySlide)),
            landingRipple: progress(time, in: landingRippleSpread),
            wordProgress: taglineWords.indices.map { index in
                let start = taglineStart + Double(index) * wordStagger
                return easeOut(progress(time, in: start ... start + wordDuration))
            }
        )
    }

    /// The fully drawn splash, used when Reduce Motion is on.
    static var finalFrame: Frame { frame(at: duration) }

    // MARK: Relay path

    /// Center of the pin's ball in lockup points.
    static var pinCenter: CGPoint {
        CGPoint(
            x: markOrigin.x + TravelantMarkGeometry.ringCenter.x,
            y: markOrigin.y + TravelantMarkGeometry.ringCenter.y
        )
    }

    /// Where the ball starts rolling: just left of the "T", resting on the baseline.
    static var rollStart: CGPoint {
        CGPoint(
            x: TravelantWordmarkGeometry.origin.x - 12,
            y: TravelantWordmarkGeometry.origin.y - TravelantWordmarkGeometry.ballDiameter * CGFloat(relayScale) / 2
        )
    }

    /// Where the last hop lands: on the "t" crossbar, where its extension begins.
    static var crossbarLanding: CGPoint {
        CGPoint(
            x: TravelantWordmarkGeometry.point(TravelantWordmarkGeometry.crossbarStart).x + 2,
            y: TravelantWordmarkGeometry.ballCenter.y
        )
    }

    static func relayBall(at time: TimeInterval) -> RelayBall? {
        guard time >= relayAppear.lowerBound else { return nil }
        let appear = easeOut(progress(time, in: relayAppear))
        let size = relayScale + (1 - relayScale) * easeOut(progress(time, in: relaySlide))
        let pulse = 1 + landingPulseScale * sin(.pi * progress(time, in: landingPulse))
        let arcLength = relayArc.upperBound - relayArc.lowerBound
        return RelayBall(
            center: relayCenter(at: time),
            diameter: TravelantWordmarkGeometry.ballDiameter * CGFloat(appear * size * pulse),
            isBehindMark: time < relayArc.lowerBound + 0.35 * arcLength
        )
    }

    /// Center of the relay ball in lockup points.
    static func relayCenter(at time: TimeInterval) -> CGPoint {
        if time < relayRoll.lowerBound {
            let arc = easeInOutSine(progress(time, in: relayArc))
            let from = CGPoint(x: pinCenter.x, y: pinCenter.y + 6)
            return CGPoint(
                x: lerp(from.x, rollStart.x, arc),
                y: lerp(from.y, rollStart.y, arc) - arcHeight * CGFloat(sin(.pi * arc))
            )
        }
        if time < relaySlide.lowerBound {
            let roll = progress(time, in: relayRoll)
            let count = hopHeights.count
            let hop = min(count - 1, Int(roll * Double(count)))
            let within = roll * Double(count) - Double(hop)
            let landing = hop == count - 1 ? crossbarLanding.y : rollStart.y
            return CGPoint(
                x: lerp(rollStart.x, crossbarLanding.x, easeInOutSine(roll)),
                y: lerp(rollStart.y, landing, easeInOut(within)) - hopHeights[hop] * CGFloat(sin(.pi * within))
            )
        }
        let slide = easeOut(progress(time, in: relaySlide))
        return CGPoint(x: lerp(crossbarLanding.x, TravelantWordmarkGeometry.ballCenter.x, slide), y: crossbarLanding.y)
    }

    /// When the rolling ball reaches each letter's center.
    static let letterPassTimes: [Double] = TravelantWordmarkGeometry.letterCenters.map { center in
        stride(from: relayRoll.lowerBound, to: relaySlide.lowerBound, by: 0.004)
            .first { relayCenter(at: $0).x >= center.x - 6 } ?? relaySlide.lowerBound
    }

    // MARK: Easing

    /// Fraction of the route drawn at `time`, interpolated between the video keyframes.
    static func drawProgress(at time: TimeInterval) -> Double {
        guard let first = drawKeyframes.first, time > first.time else { return 0 }
        for (previous, next) in zip(drawKeyframes, drawKeyframes.dropFirst()) where time <= next.time {
            let fraction = (time - previous.time) / (next.time - previous.time)
            return previous.progress + (next.progress - previous.progress) * fraction
        }
        return 1
    }

    static func progress(_ time: TimeInterval, in range: ClosedRange<Double>) -> Double {
        min(max((time - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    static func easeInOut(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }

    static func easeInOutSine(_ value: Double) -> Double {
        (1 - cos(.pi * value)) / 2
    }

    static func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    /// Overshoots slightly before settling, for pop-ins.
    static func easeOutBack(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(value - 1, 3) + c1 * pow(value - 1, 2)
    }

    /// A damped spring from 0 to 1 that overshoots and settles; `bounce` (0…1) sets how lively.
    static func spring(_ value: Double, bounce: Double) -> Double {
        guard value > 0 else { return 0 }
        guard value < 1 else { return 1 }
        let damping = 7 * (1 - bounce) + 2.2
        let frequency = Double.pi * (1.2 + 3.2 * bounce)
        return 1 - exp(-damping * value) * cos(frequency * value) * pow(1 - value, 0.15)
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: Double) -> CGFloat {
        from + (to - from) * CGFloat(fraction)
    }

    private static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: Double) -> CGPoint {
        let t = CGFloat(t)
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }
}
