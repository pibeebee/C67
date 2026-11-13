import CoreGraphics
import Foundation

/// Geometry of the italic "Travelant" wordmark (`Travelant-Wordmark-White.svg`) under the pin
/// mark in the splash lockup.
///
/// Glyphs are stored upright in font units (baseline at y = 0, cap height 149) and slanted 11°
/// as they are mapped into the `SplashTimeline.lockupSize` box. The coral ball sits at the end of
/// the "t" crossbar.
enum TravelantWordmarkGeometry {
    /// One outline command in font units. `quad` is `(x, y, controlX, controlY)`.
    enum Segment: Sendable {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case quad(CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    /// The wordmark's 11° italic slant.
    static let slant = CGFloat(tan(11 * Double.pi / 180))
    /// Points per font unit: the cap height is about 37 pt.
    static let scale: CGFloat = 0.25
    /// Left end of the baseline inside the lockup box. Centers the word and its ball under the mark.
    static let origin = CGPoint(x: 0.125, y: 252)

    /// The "t" crossbar reaches out to the ball along this line (font units).
    static let crossbarStart = CGPoint(x: 815.2, y: -96.2)
    static let crossbarEnd = CGPoint(x: 896.8, y: -96.2)
    static let crossbarWidth: CGFloat = 26.8 * scale

    /// The coral ball stays round, so its center is placed without the slant.
    static let ballCenter = CGPoint(x: origin.x + 912 * scale, y: origin.y - 96.2 * scale)
    static let ballDiameter: CGFloat = 42 * scale

    /// Maps a point in font units to the lockup box, applying the slant.
    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + (x - slant * y) * scale, y: origin.y + y * scale)
    }

    static func point(_ unit: CGPoint) -> CGPoint {
        point(unit.x, unit.y)
    }

    /// Upright bounds of each glyph in font units, from its outline and control points.
    static let glyphBounds: [CGRect] = glyphs.map { segments in
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func include(_ x: CGFloat, _ y: CGFloat) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        for segment in segments {
            switch segment {
            case let .move(x, y), let .line(x, y):
                include(x, y)
            case let .quad(x, y, controlX, controlY):
                include(x, y)
                include(controlX, controlY)
            case .close:
                break
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Middle of each letter's baseline in the lockup box: the letter stands up from here.
    static let letterPivots: [CGPoint] = glyphBounds.map { point($0.midX, $0.maxY) }

    /// Center of each letter in the lockup box: the rolling ball passes over it.
    static let letterCenters: [CGPoint] = glyphBounds.map { point($0.midX, $0.midY) }

    /// Outlines of T, r, a, v, e, l, a, n, t, in order.
    static let glyphs: [[Segment]] = [
        // T
        [
            .move(71, 0), .line(40, 0), .line(40, -122), .line(2.2, -122), .line(2.2, -149), .line(108.2, -149),
            .line(108.2, -122), .line(71, -122), .line(71, 0), .close
        ],
        // r
        [
            .move(134.4, 0), .line(104.4, 0), .line(104.4, -109.2), .line(132.4, -109.2), .line(132.4, -93),
            .quad(142.4, -105.6, 136, -101.8), .line(142.4, -105.6), .quad(162, -110.4, 150.6, -110.4),
            .line(162, -110.4), .line(168.4, -110.4), .line(168.4, -84.4), .line(159, -84.4),
            .quad(141.2, -77.7, 148, -84.4), .quad(134.4, -58.8, 134.4, -71), .line(134.4, -58.8), .line(134.4, 0),
            .close
        ],
        // a
        [
            .move(210.4, 2.4), .line(210.4, 2.4), .quad(190, -1.4, 198.6, 2.4), .quad(176.8, -12.3, 181.4, -5.2),
            .quad(172.2, -29.2, 172.2, -19.4), .line(172.2, -29.2), .quad(176.4, -45.5, 172.2, -38.4),
            .quad(189.3, -57.4, 180.6, -52.6), .quad(211, -64.2, 198, -62.2), .line(211, -64.2), .line(241.2, -69),
            .line(241.2, -72), .quad(236.3, -82.4, 241.2, -78.2), .quad(223, -86.6, 231.4, -86.6), .line(223, -86.6),
            .quad(208.9, -82.2, 215, -86.6), .quad(200, -70.6, 202.8, -77.8), .line(200, -70.6), .line(176, -82),
            .quad(186.2, -97.8, 179.2, -91.2), .quad(203, -108, 193.2, -104.4), .quad(224.4, -111.6, 212.8, -111.6),
            .line(224.4, -111.6), .quad(248.8, -106.6, 238.2, -111.6), .quad(265.3, -92.7, 259.4, -101.6),
            .quad(271.2, -72, 271.2, -83.8), .line(271.2, -72), .line(271.2, 0), .line(243.2, 0),
            .line(243.2, -10.4), .quad(239.4, -7, 241.4, -8.4), .line(239.4, -7), .quad(226.4, 0.1, 233.6, -2.2),
            .quad(210.4, 2.4, 219.2, 2.4), .close, .move(241.2, -43.6), .line(241.2, -47), .line(216.4, -42.6),
            .quad(206.6, -38.5, 210, -41.4), .quad(203.2, -30.2, 203.2, -35.6), .line(203.2, -30.2),
            .quad(207, -22.4, 203.2, -25.2), .quad(216.4, -19.6, 210.8, -19.6), .line(216.4, -19.6),
            .quad(229.4, -22.8, 223.8, -19.6), .quad(238.1, -31.5, 235, -26), .quad(241.2, -43.6, 241.2, -37),
            .line(241.2, -43.6), .close
        ],
        // v
        [
            .move(346.4, 0), .line(320.4, 0), .line(277.4, -109.2), .line(309.8, -109.2), .line(333.4, -43.8),
            .line(357, -109.2), .line(389.4, -109.2), .line(346.4, 0), .close
        ],
        // e
        [
            .move(448.2, 2.4), .line(448.2, 2.4), .quad(418, -5.3, 430.8, 2.4), .quad(398.2, -26, 405.2, -13),
            .quad(391.2, -54.8, 391.2, -39), .line(391.2, -54.8), .quad(398.5, -84, 391.2, -71.2),
            .quad(418.2, -104.2, 405.8, -96.8), .quad(446.2, -111.6, 430.6, -111.6), .line(446.2, -111.6),
            .quad(469.2, -107.5, 459.2, -111.6), .quad(486.1, -96, 479.2, -103.4), .quad(496.6, -78.9, 493, -88.6),
            .quad(500.2, -57.8, 500.2, -69.2), .line(500.2, -57.8), .quad(499.9, -51.5, 500.2, -54.6),
            .quad(498.8, -46.2, 499.6, -48.4), .line(498.8, -46.2), .line(422.4, -46.2),
            .quad(424.4, -38.4, 422.8, -42), .line(424.4, -38.4), .quad(433.6, -27.5, 427.4, -31.4),
            .quad(448.6, -23.6, 439.8, -23.6), .line(448.6, -23.6), .quad(462.3, -26.8, 456.6, -23.6),
            .quad(471.2, -35.6, 468, -30), .line(471.2, -35.6), .line(495.2, -24.2), .quad(485.1, -10.2, 492, -16.2),
            .quad(468.8, -0.9, 478.2, -4.2), .quad(448.2, 2.4, 459.4, 2.4), .close, .move(423, -68.2),
            .line(423, -68.2), .line(468.4, -68.2), .quad(467.4, -73.2, 468.2, -70.8), .line(467.4, -73.2),
            .quad(459.7, -83.7, 465.2, -79.8), .quad(446.2, -87.6, 454.2, -87.6), .line(446.2, -87.6),
            .quad(432.8, -83.8, 438.4, -87.6), .quad(424.4, -72.6, 427.2, -80), .line(424.4, -72.6),
            .quad(423, -68.2, 423.6, -70.6), .close
        ],
        // l
        [
            .move(542.8, 0), .line(512.8, 0), .line(512.8, -151.4), .line(542.8, -151.4), .line(542.8, 0), .close
        ],
        // a
        [
            .move(593.6, 2.4), .line(593.6, 2.4), .quad(573.2, -1.4, 581.8, 2.4), .quad(560, -12.3, 564.6, -5.2),
            .quad(555.4, -29.2, 555.4, -19.4), .line(555.4, -29.2), .quad(559.6, -45.5, 555.4, -38.4),
            .quad(572.5, -57.4, 563.8, -52.6), .quad(594.2, -64.2, 581.2, -62.2), .line(594.2, -64.2),
            .line(624.4, -69), .line(624.4, -72), .quad(619.5, -82.4, 624.4, -78.2),
            .quad(606.2, -86.6, 614.6, -86.6), .line(606.2, -86.6), .quad(592.1, -82.2, 598.2, -86.6),
            .quad(583.2, -70.6, 586, -77.8), .line(583.2, -70.6), .line(559.2, -82),
            .quad(569.4, -97.8, 562.4, -91.2), .quad(586.2, -108, 576.4, -104.4), .quad(607.6, -111.6, 596, -111.6),
            .line(607.6, -111.6), .quad(632, -106.6, 621.4, -111.6), .quad(648.5, -92.7, 642.6, -101.6),
            .quad(654.4, -72, 654.4, -83.8), .line(654.4, -72), .line(654.4, 0), .line(626.4, 0),
            .line(626.4, -10.4), .quad(622.6, -7, 624.6, -8.4), .line(622.6, -7), .quad(609.6, 0.1, 616.8, -2.2),
            .quad(593.6, 2.4, 602.4, 2.4), .close, .move(624.4, -43.6), .line(624.4, -47), .line(599.6, -42.6),
            .quad(589.8, -38.5, 593.2, -41.4), .quad(586.4, -30.2, 586.4, -35.6), .line(586.4, -30.2),
            .quad(590.2, -22.4, 586.4, -25.2), .quad(599.6, -19.6, 594, -19.6), .line(599.6, -19.6),
            .quad(612.6, -22.8, 607, -19.6), .quad(621.3, -31.5, 618.2, -26), .quad(624.4, -43.6, 624.4, -37),
            .line(624.4, -43.6), .close
        ],
        // n
        [
            .move(701.4, 0), .line(671.4, 0), .line(671.4, -109.2), .line(699.4, -109.2), .line(699.4, -96),
            .quad(710.2, -107, 703.2, -103), .line(710.2, -107), .quad(730, -111.6, 718.6, -111.6),
            .line(730, -111.6), .quad(751.7, -106.4, 742.4, -111.6), .quad(766.2, -91.9, 761, -101.2),
            .quad(771.4, -70.2, 771.4, -82.6), .line(771.4, -70.2), .line(771.4, 0), .line(741.4, 0),
            .line(741.4, -63.8), .quad(738.9, -74.8, 741.4, -70.2), .quad(731.9, -82, 736.4, -79.4),
            .quad(721.4, -84.6, 727.4, -84.6), .line(721.4, -84.6), .quad(711, -82, 715.6, -84.6),
            .quad(703.9, -74.8, 706.4, -79.4), .quad(701.4, -63.8, 701.4, -70.2), .line(701.4, -63.8),
            .line(701.4, 0), .close
        ],
        // t
        [
            .move(838.8, 1.2), .line(838.8, 1.2), .quad(808.1, -9.5, 819, 1.2), .quad(797.2, -39.4, 797.2, -20.2),
            .line(797.2, -39.4), .line(797.2, -83.2), .line(778.8, -83.2), .line(778.8, -109.2),
            .line(779.8, -109.2), .quad(792.7, -113.4, 788.2, -109.2), .quad(797.2, -126, 797.2, -117.6),
            .line(797.2, -126), .line(797.2, -134), .line(827.2, -134), .line(827.2, -109.2), .line(852.8, -109.2),
            .line(852.8, -83.2), .line(827.2, -83.2), .line(827.2, -41.4), .quad(829.2, -32.1, 827.2, -35.8),
            .quad(835.4, -26.6, 831.2, -28.4), .quad(845.8, -24.8, 839.6, -24.8), .line(845.8, -24.8),
            .quad(849, -25, 847.2, -24.8), .quad(852.8, -25.4, 850.8, -25.2), .line(852.8, -25.4), .line(852.8, 0),
            .quad(846, 0.8, 849.8, 0.4), .quad(838.8, 1.2, 842.2, 1.2), .close
        ],
    ]
}
