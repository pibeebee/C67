import SwiftUI

/// The glossy orange ball of the Travelant mark, with its light halo and soft shadow.
///
/// Uses the Figma export `SplashBall` (Travelant — Logo Animation › Pin). `diameter` is the
/// orange ball itself; the halo and shadow extend beyond it.
struct TravelantBall: View {
    var diameter: CGFloat

    /// The orange ball spans 111 of the asset's 184 px.
    private static let assetToBall: CGFloat = 184 / 111
    /// The asset's shadow sits below the ball, so the ball's center is 0.5 px left of and 12.5 px
    /// above the image center. Shifting by this keeps the ball itself on the given position.
    private static let ballOffset = CGSize(width: 0.5 / 111, height: 12.5 / 111)

    var body: some View {
        Image("SplashBall")
            .resizable()
            .frame(width: diameter * Self.assetToBall, height: diameter * Self.assetToBall)
            .offset(x: diameter * Self.ballOffset.width, y: diameter * Self.ballOffset.height)
            .accessibilityHidden(true)
    }
}
