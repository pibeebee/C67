import CoreGraphics
import Foundation

/// Geometry of the Travelant pin mark in a 160 × 200 pt design box.
///
/// `centerLine` is the skeleton of the Figma export `SplashRoute`, from the tail tip up and
/// clockwise around the ring to its lower-right end, resampled evenly by length. It drives both
/// the reveal mask and the drawing ball, so the ball stays centered on the white route.
enum TravelantMarkGeometry {
    static let designSize = CGSize(width: 160, height: 200)
    /// Where the ball rests: the center of the route's ring, fitted to both the inner and outer
    /// edges of the Figma export (they agree within 0.03 pt).
    static let ringCenter = CGPoint(x: 80.22, y: 104.93)
    static let ballDiameter: CGFloat = 40
    static let penDiameter: CGFloat = 24

    /// Evenly spaced points along the route's center line (96 points, ~342 pt long), taken from
    /// the opaque body of the export so the ball stays within about 1 pt of the white stroke's middle.
    static let centerLine: [CGPoint] = [
        CGPoint(x: 81.36, y: 186.90), CGPoint(x: 78.80, y: 184.34), CGPoint(x: 76.24, y: 181.78), CGPoint(x: 73.68, y: 179.22),
        CGPoint(x: 71.12, y: 176.66), CGPoint(x: 68.56, y: 174.10), CGPoint(x: 66.00, y: 171.54), CGPoint(x: 63.44, y: 168.98),
        CGPoint(x: 60.88, y: 166.42), CGPoint(x: 58.32, y: 163.86), CGPoint(x: 55.76, y: 161.30), CGPoint(x: 53.20, y: 158.74),
        CGPoint(x: 50.64, y: 156.18), CGPoint(x: 48.08, y: 153.62), CGPoint(x: 45.52, y: 151.06), CGPoint(x: 42.96, y: 148.50),
        CGPoint(x: 40.40, y: 145.94), CGPoint(x: 37.89, y: 143.33), CGPoint(x: 35.53, y: 140.59), CGPoint(x: 33.36, y: 137.69),
        CGPoint(x: 31.42, y: 134.64), CGPoint(x: 29.67, y: 131.47), CGPoint(x: 28.15, y: 128.18), CGPoint(x: 26.84, y: 124.81),
        CGPoint(x: 25.80, y: 121.34), CGPoint(x: 24.97, y: 117.82), CGPoint(x: 24.36, y: 114.25), CGPoint(x: 23.94, y: 110.65),
        CGPoint(x: 23.58, y: 107.05), CGPoint(x: 23.54, y: 103.43), CGPoint(x: 23.88, y: 99.83), CGPoint(x: 24.29, y: 96.23),
        CGPoint(x: 24.83, y: 92.65), CGPoint(x: 25.64, y: 89.12), CGPoint(x: 26.66, y: 85.65), CGPoint(x: 27.91, y: 82.25),
        CGPoint(x: 29.40, y: 78.96), CGPoint(x: 31.14, y: 75.78), CGPoint(x: 33.09, y: 72.73), CGPoint(x: 35.26, y: 69.84),
        CGPoint(x: 37.57, y: 67.05), CGPoint(x: 40.05, y: 64.41), CGPoint(x: 42.69, y: 61.93), CGPoint(x: 45.49, y: 59.65),
        CGPoint(x: 48.42, y: 57.53), CGPoint(x: 51.50, y: 55.62), CGPoint(x: 54.71, y: 53.94), CGPoint(x: 58.02, y: 52.47),
        CGPoint(x: 61.42, y: 51.25), CGPoint(x: 64.90, y: 50.26), CGPoint(x: 68.44, y: 49.47), CGPoint(x: 72.02, y: 48.96),
        CGPoint(x: 75.62, y: 48.55), CGPoint(x: 79.23, y: 48.24), CGPoint(x: 82.84, y: 48.35), CGPoint(x: 86.44, y: 48.72),
        CGPoint(x: 90.04, y: 49.16), CGPoint(x: 93.60, y: 49.81), CGPoint(x: 97.11, y: 50.67), CGPoint(x: 100.56, y: 51.76),
        CGPoint(x: 103.93, y: 53.08), CGPoint(x: 107.20, y: 54.63), CGPoint(x: 110.36, y: 56.41), CGPoint(x: 113.39, y: 58.39),
        CGPoint(x: 116.27, y: 60.58), CGPoint(x: 118.99, y: 62.97), CGPoint(x: 121.56, y: 65.52), CGPoint(x: 123.96, y: 68.22),
        CGPoint(x: 126.18, y: 71.09), CGPoint(x: 128.23, y: 74.07), CGPoint(x: 130.05, y: 77.20), CGPoint(x: 131.64, y: 80.45),
        CGPoint(x: 133.00, y: 83.80), CGPoint(x: 134.14, y: 87.24), CGPoint(x: 135.02, y: 90.75), CGPoint(x: 135.73, y: 94.30),
        CGPoint(x: 136.24, y: 97.88), CGPoint(x: 136.62, y: 101.49), CGPoint(x: 136.83, y: 105.10), CGPoint(x: 136.60, y: 108.71),
        CGPoint(x: 136.22, y: 112.31), CGPoint(x: 135.69, y: 115.89), CGPoint(x: 134.97, y: 119.44), CGPoint(x: 134.06, y: 122.94),
        CGPoint(x: 132.86, y: 126.36), CGPoint(x: 131.47, y: 129.70), CGPoint(x: 129.83, y: 132.92), CGPoint(x: 128.01, y: 136.06),
        CGPoint(x: 126.01, y: 139.07), CGPoint(x: 123.82, y: 141.95), CGPoint(x: 121.46, y: 144.70), CGPoint(x: 119.18, y: 147.51),
        CGPoint(x: 116.89, y: 150.32), CGPoint(x: 114.61, y: 153.13), CGPoint(x: 112.32, y: 155.93), CGPoint(x: 110.04, y: 158.74),
    ]

    /// Distance along `centerLine` at each point, starting at 0.
    private static let cumulativeLengths: [CGFloat] = {
        var lengths: [CGFloat] = [0]
        for (previous, next) in zip(centerLine, centerLine.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(next.x - previous.x, next.y - previous.y))
        }
        return lengths
    }()

    static var totalLength: CGFloat { cumulativeLengths.last ?? 0 }
    static var tailTip: CGPoint { centerLine[0] }
    static var routeEnd: CGPoint { centerLine[centerLine.count - 1] }

    /// The point reached after drawing `progress` (0…1) of the route, by length.
    static func point(at progress: Double) -> CGPoint {
        let target = CGFloat(min(max(progress, 0), 1)) * totalLength
        guard target > 0 else { return tailTip }
        guard target < totalLength else { return routeEnd }
        var upper = 1
        while cumulativeLengths[upper] < target { upper += 1 }
        let lower = upper - 1
        let span = cumulativeLengths[upper] - cumulativeLengths[lower]
        let fraction = span > 0 ? (target - cumulativeLengths[lower]) / span : 0
        let a = centerLine[lower]
        let b = centerLine[upper]
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    /// How far the reveal mask reaches past each end of the center line, enough to uncover the
    /// route's round caps (body half-width about 11.6 pt) and part of their soft shadow.
    static let revealExtension: CGFloat = 16

    /// The reveal path's length: the center line plus an extension at each end.
    static var revealLength: CGFloat { totalLength + 2 * revealExtension }

    /// Trim end for the reveal mask after drawing `progress` of the route.
    ///
    /// While drawing, the mask ends flat exactly at `point(at: progress)`, the ball's center, so
    /// the white route never runs ahead of the ball. The far cap is uncovered once the route is complete.
    static func revealTrimEnd(for progress: Double) -> CGFloat {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        return (revealExtension + CGFloat(progress) * totalLength) / revealLength
    }

    /// The center line extended straight past both ends by `revealExtension`.
    static var revealLine: [CGPoint] {
        func extended(_ end: CGPoint, awayFrom neighbor: CGPoint) -> CGPoint {
            let dx = end.x - neighbor.x
            let dy = end.y - neighbor.y
            let length = hypot(dx, dy)
            return CGPoint(x: end.x + dx / length * revealExtension, y: end.y + dy / length * revealExtension)
        }
        let first = extended(centerLine[0], awayFrom: centerLine[1])
        let last = extended(centerLine[centerLine.count - 1], awayFrom: centerLine[centerLine.count - 2])
        return [first] + centerLine + [last]
    }

    static func scale(for rect: CGRect) -> CGFloat {
        rect.width / designSize.width
    }

    static func mapped(_ point: CGPoint, into rect: CGRect) -> CGPoint {
        let scale = scale(for: rect)
        return CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
    }
}
