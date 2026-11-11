import SwiftUI

/// One letter of the italic Travelant wordmark, drawn where it sits in the splash lockup.
///
/// Give it the lockup's frame (`SplashTimeline.lockupSize`) so every letter lines up.
struct TravelantWordmarkLetter: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func mapped(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let point = TravelantWordmarkGeometry.point(x, y)
            return CGPoint(x: rect.minX + point.x, y: rect.minY + point.y)
        }
        for segment in TravelantWordmarkGeometry.glyphs[index] {
            switch segment {
            case let .move(x, y):
                path.move(to: mapped(x, y))
            case let .line(x, y):
                path.addLine(to: mapped(x, y))
            case let .quad(x, y, controlX, controlY):
                path.addQuadCurve(to: mapped(x, y), control: mapped(controlX, controlY))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

/// The extension of the "t" crossbar that reaches out to the coral ball. Stroke it with
/// `TravelantWordmarkGeometry.crossbarWidth` and round caps; trim it to draw it out.
struct TravelantWordmarkCrossbar: Shape {
    func path(in rect: CGRect) -> Path {
        let start = TravelantWordmarkGeometry.point(TravelantWordmarkGeometry.crossbarStart)
        let end = TravelantWordmarkGeometry.point(TravelantWordmarkGeometry.crossbarEnd)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + start.x, y: rect.minY + start.y))
        path.addLine(to: CGPoint(x: rect.minX + end.x, y: rect.minY + end.y))
        return path
    }
}
