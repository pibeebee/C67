import CoreGraphics
import SwiftUI

/// Placement of the Figma logo exports (Travelant — Logo Animation) inside the
/// `TravelantMarkGeometry` 160 × 200 pt design box.
///
/// The exports share one scale (0.364 pt per px). Positions were aligned against the brand
/// splash video and the Figma app icon.
enum TravelantMarkAssets {
    struct Placement: Sendable {
        let name: String
        let frame: CGRect
        /// Where the antenna stem meets the ring, relative to `frame`; the antenna grows and
        /// waves around this point.
        let anchor: UnitPoint

        var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    }

    static let route = Placement(
        name: "SplashRoute",
        frame: CGRect(x: -7.66, y: 27.26, width: 176.2, height: 201.3),
        anchor: .center
    )

    static let leadingAntenna = Placement(
        name: "SplashAntennaLeft",
        frame: CGRect(x: -12.5, y: 2.1, width: 105.6, height: 95.7),
        anchor: UnitPoint(x: 0.586, y: 0.513)
    )

    static let trailingAntenna = Placement(
        name: "SplashAntennaRight",
        frame: CGRect(x: 67.8, y: 2.1, width: 105.2, height: 95.7),
        anchor: UnitPoint(x: 0.405, y: 0.513)
    )

    static var antennas: [Placement] { [leadingAntenna, trailingAntenna] }

    /// Width of the mask that reveals the route along its center line. The route body is about
    /// 23 pt wide; 48 pt keeps most of its soft shadow while staying clear of the ring's end
    /// as the tail is drawn. The mask ends flat at the ball's center, which covers the cut.
    static let revealWidth: CGFloat = 48
}
