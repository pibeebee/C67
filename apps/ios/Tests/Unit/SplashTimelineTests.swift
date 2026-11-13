import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import C67

/// Checks the splash animation against moments sampled from `Travelant-Splash-iPhone17.mp4`
/// and the "Ball relay" wordmark option.
@Suite("Splash animation timeline")
struct SplashTimelineTests {
    @Test("The route starts at the tail tip and ends on the ring's lower right")
    func routeEndpoints() {
        let start = TravelantMarkGeometry.point(at: 0)
        let end = TravelantMarkGeometry.point(at: 1)
        // The ends are the centers of the Figma route's round caps; the video's ball is within 6 pt.
        #expect(distance(start, CGPoint(x: 81.36, y: 186.9)) < 0.5)
        #expect(distance(end, CGPoint(x: 110.04, y: 158.74)) < 0.5)
        #expect(distance(start, CGPoint(x: 81.75, y: 183.25)) < 6)
        #expect(distance(end, CGPoint(x: 108.2, y: 154)) < 6)
    }

    @Test("Route points are evenly spaced, so the reveal and the ball stay together")
    func routeIsEvenlySpaced() {
        let line = TravelantMarkGeometry.centerLine
        let steps = zip(line, line.dropFirst()).map { distance($0, $1) }
        let average = steps.reduce(0, +) / CGFloat(steps.count)
        #expect(steps.allSatisfy { abs($0 - average) < 0.5 })
    }

    @Test("While drawing, the white route ends exactly at the ball's center", arguments: [0.1, 0.35, 0.6, 0.9])
    func revealEndsAtBall(progress: Double) {
        let line = TravelantMarkGeometry.revealLine
        let lengths = zip(line, line.dropFirst()).map { distance($0, $1) }
        let total = lengths.reduce(0, +)
        #expect(abs(total - TravelantMarkGeometry.revealLength) < 0.01)
        let reach = TravelantMarkGeometry.revealTrimEnd(for: progress) * total
        let drawn = reach - TravelantMarkGeometry.revealExtension
        #expect(abs(drawn - CGFloat(progress) * TravelantMarkGeometry.totalLength) < 0.01)
    }

    @Test("The reveal is empty before drawing and complete, caps included, after it")
    func revealBounds() {
        #expect(TravelantMarkGeometry.revealTrimEnd(for: 0) == 0)
        #expect(TravelantMarkGeometry.revealTrimEnd(for: 1) == 1)
    }

    @Test("The ball follows the video's pace along the route", arguments: [
        (0.83, 0.12), (1.03, 0.26), (1.33, 0.54), (1.63, 0.79), (1.93, 0.96),
    ])
    func drawPace(time: Double, expected: Double) {
        #expect(abs(SplashTimeline.drawProgress(at: time) - expected) < 0.001)
    }

    @Test("Before 0.33 s only the gradient shows")
    func emptyStart() {
        let frame = SplashTimeline.frame(at: 0.2)
        #expect(frame.penScale == 0)
        #expect(frame.drawProgress == 0)
        #expect(frame.antennaScale.allSatisfy { $0 == 0 })
        #expect(frame.relayBall == nil)
        #expect(frame.letterOpacity.allSatisfy { $0 == 0 })
        #expect(frame.crossbarProgress == 0)
        #expect(frame.wordProgress.allSatisfy { $0 == 0 })
    }

    @Test("The pen sits at the tail tip before drawing starts")
    func penAtTailTip() {
        let frame = SplashTimeline.frame(at: 0.55)
        #expect(frame.penScale == 1)
        #expect(frame.ballCenter == TravelantMarkGeometry.tailTip)
        #expect(frame.ballDiameter == TravelantMarkGeometry.penDiameter)
    }

    @Test("The pen leads the stroke while drawing", arguments: [0.9, 1.2, 1.5, 1.8, 2.05])
    func penFollowsStroke(time: Double) {
        let frame = SplashTimeline.frame(at: time)
        #expect(frame.drawProgress > 0 && frame.drawProgress < 1)
        #expect(frame.ballCenter == TravelantMarkGeometry.point(at: frame.drawProgress))
    }

    @Test("The ball hops up, across and down into the ring center")
    func ballHops() {
        let launch = SplashTimeline.frame(at: 2.27)
        let across = SplashTimeline.frame(at: 2.4)
        #expect(launch.ballCenter.y < TravelantMarkGeometry.ringCenter.y)
        #expect(across.ballCenter.y < TravelantMarkGeometry.ringCenter.y)
        #expect(across.ballCenter.x < launch.ballCenter.x)
        #expect(launch.ballDiameter > TravelantMarkGeometry.ballDiameter)
    }

    @Test("The ball settles in the ring center at full size after the hop")
    func ballSettles() {
        let frame = SplashTimeline.frame(at: 2.6)
        #expect(frame.drawProgress == 1)
        #expect(frame.ballCenter == TravelantMarkGeometry.ringCenter)
        #expect(abs(frame.ballDiameter - TravelantMarkGeometry.ballDiameter) < 0.01)
    }

    @Test("The ball pulses twice", arguments: [2.76, 3.06])
    func pulsePeaks(time: Double) {
        #expect(SplashTimeline.frame(at: time).ballDiameter > TravelantMarkGeometry.ballDiameter * 1.1)
    }

    @Test("The ball is at rest between and after the pulses", arguments: [2.915, 3.3])
    func pulseRest(time: Double) {
        #expect(abs(SplashTimeline.frame(at: time).ballDiameter - TravelantMarkGeometry.ballDiameter) < 0.5)
    }

    @Test("Antennae are hidden at 3.4 s, the trailing one grows a little later, and both settle by 3.85 s")
    func antennaeGrow() {
        #expect(SplashTimeline.frame(at: 3.4).antennaScale == [0, 0])
        let early = SplashTimeline.frame(at: 3.48).antennaScale
        #expect(early[0] > 0 && early[1] == 0)
        #expect(SplashTimeline.frame(at: 3.85).antennaScale == [1, 1])
    }

    @Test("Antennae wave outward, swing back, then rest")
    func antennaeWave() {
        #expect(SplashTimeline.frame(at: 4.0).antennaAngle == [0, 0])
        let outward = SplashTimeline.frame(at: 4.2).antennaAngle
        #expect(outward[0] < -5)
        #expect(outward[1] > 0)
        let back = SplashTimeline.frame(at: 4.36).antennaAngle
        #expect(back[0] > 3)
        #expect(SplashTimeline.frame(at: 4.6).antennaAngle.allSatisfy { abs($0) < 0.001 })
    }

    @Test("The relay ball slips out from behind the pin's ball, then travels in front")
    func relayBallLeavesThePin() throws {
        #expect(SplashTimeline.frame(at: 4.45).relayBall == nil)
        let start = try #require(SplashTimeline.frame(at: 4.52).relayBall)
        #expect(start.isBehindMark)
        #expect(distance(start.center, SplashTimeline.pinCenter) < 8)
        let arc = try #require(SplashTimeline.frame(at: 4.8).relayBall)
        #expect(!arc.isBehindMark)
        #expect(arc.center.x < SplashTimeline.pinCenter.x)
    }

    @Test("The relay ball rolls left to right along the baseline")
    func relayBallRolls() {
        let times = stride(from: 4.95, through: 6.35, by: 0.05)
        let xs = times.map { SplashTimeline.relayCenter(at: $0).x }
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 <= $1 + 0.001 })
        #expect(abs(SplashTimeline.relayCenter(at: 4.95).y - SplashTimeline.rollStart.y) < 0.01)
        #expect(SplashTimeline.relayCenter(at: 5.1).y < SplashTimeline.rollStart.y)
    }

    @Test("Letters spring up from the baseline in order as the ball passes them")
    func lettersFollowTheBall() {
        let passes = SplashTimeline.letterPassTimes
        #expect(passes.count == TravelantWordmarkGeometry.glyphs.count)
        #expect(zip(passes, passes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(passes.allSatisfy { SplashTimeline.relayRoll.contains($0) })

        let mid = SplashTimeline.frame(at: 5.5)
        #expect((mid.letterOpacity.first ?? 0) == 1)
        #expect(mid.letterOpacity.last == 0)
        #expect(zip(mid.letterOpacity, mid.letterOpacity.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test("A letter overshoots as it springs up, then settles upright")
    func letterOvershoots() {
        let pass = SplashTimeline.letterPassTimes[0]
        let pops = stride(from: pass, through: pass + 0.5, by: 0.01).map { SplashTimeline.frame(at: $0).letterPop[0] }
        #expect(pops.contains { $0 > 1.02 })
        #expect(SplashTimeline.frame(at: pass + 0.6).letterPop[0] == 1)
    }

    @Test("The ball pulls the t crossbar out and parks at its end with a pulse and ripple")
    func ballParksOnTheCrossbar() throws {
        let rolling = SplashTimeline.frame(at: 6.0)
        #expect(rolling.crossbarProgress == 0)
        let sliding = SplashTimeline.frame(at: 6.2)
        #expect(sliding.crossbarProgress > 0 && sliding.crossbarProgress < 1)

        let pulse = try #require(SplashTimeline.frame(at: 6.49).relayBall)
        #expect(pulse.diameter > TravelantWordmarkGeometry.ballDiameter * 1.3)
        let ripple = SplashTimeline.frame(at: 6.6).landingRipple
        #expect(ripple > 0 && ripple < 1)
    }

    @Test("The tagline follows once the ball has parked, word by word")
    func taglineFollows() {
        #expect(SplashTimeline.taglineWords == ["Your", "trip", "planner", "bestie"])
        let early = SplashTimeline.frame(at: 6.25)
        #expect(early.letterOpacity.allSatisfy { $0 == 1 })
        #expect(early.wordProgress.allSatisfy { $0 == 0 })
        let mid = SplashTimeline.frame(at: 6.45)
        #expect(mid.wordProgress.first ?? 0 > 0)
        #expect(mid.wordProgress.last == 0)
    }

    @Test("Everything has settled at the end")
    func finalFrame() throws {
        let frame = SplashTimeline.finalFrame
        #expect(frame.penScale == 1)
        #expect(frame.drawProgress == 1)
        #expect(frame.antennaScale == [1, 1])
        #expect(frame.pulseProgress == [1, 1])
        #expect(frame.ballCenter == TravelantMarkGeometry.ringCenter)
        #expect(frame.letterPop.allSatisfy { $0 == 1 })
        #expect(frame.letterOpacity.allSatisfy { $0 == 1 })
        #expect(frame.crossbarProgress == 1)
        #expect(frame.landingRipple == 1)
        let ball = try #require(frame.relayBall)
        #expect(!ball.isBehindMark)
        #expect(distance(ball.center, TravelantWordmarkGeometry.ballCenter) < 0.001)
        #expect(abs(ball.diameter - TravelantWordmarkGeometry.ballDiameter) < 0.01)
        #expect(frame.wordProgress.allSatisfy { $0 == 1 })
        #expect(SplashTimeline.frame(at: 60) == frame)
    }

    @MainActor
    @Test("Animation moments render differently", arguments: [(0.2, 1.2), (1.2, 2.0), (3.3, 3.8), (4.0, 4.2), (3.8, 4.8), (4.8, 5.5), (5.5, 6.2), (6.2, 7.1)])
    func momentsRenderDifferently(earlier: Double, later: Double) throws {
        #expect(try png(at: earlier) != png(at: later))
    }

    @MainActor
    private func png(at time: Double) throws -> Data {
        let renderer = ImageRenderer(
            content: SplashFrameView(frame: SplashTimeline.frame(at: time)).frame(width: 402, height: 874)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }

    @MainActor
    @Test("The orange ball is centered on its position, not the asset with its shadow")
    func ballIsCenteredOnPosition() throws {
        let size: CGFloat = 120
        let renderer = ImageRenderer(
            content: TravelantBall(diameter: TravelantMarkGeometry.ballDiameter)
                .position(x: size / 2, y: size / 2)
                .frame(width: size, height: size)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let center = try #require(orangeCenter(in: image))
        #expect(abs(center.x - size / 2) < 1.5)
        #expect(abs(center.y - size / 2) < 1.5)
    }

    /// Center of the bounding box of strongly orange pixels.
    private func orangeCenter(in image: CGImage) -> CGPoint? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2]), a = Int(pixels[i + 3])
                guard a > 200, r > 200, g < 190, b < 160 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // The bitmap's first row is the top of the image, matching view coordinates.
        return CGPoint(x: CGFloat(minX + maxX) / 2, y: CGFloat(minY + maxY) / 2)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
