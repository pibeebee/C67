import SwiftUI

/// Mask path that reveals the Travelant route: its center line, extended past both ends so the
/// round caps are uncovered.
///
/// Stroke it with a butt cap and trim it to `TravelantMarkGeometry.revealTrimEnd(for:)`; the
/// trimmed end then sits exactly under the drawing ball.
struct TravelantPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(TravelantMarkGeometry.revealLine.map { TravelantMarkGeometry.mapped($0, into: rect) })
        }
    }
}
