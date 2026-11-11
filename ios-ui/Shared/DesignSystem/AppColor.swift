import SwiftUI

/// Semantic color roles shared across C67 screens.
///
/// Values live in `Resources/Colors.xcassets`, so every role adapts to Light and Dark
/// appearance. Reference these roles from features instead of raw HEX values.
enum AppColor {
    /// Screen background. Light #F2F2F7 (Sketch `Backgrounds/Light/Secondary`), Dark black.
    static let canvas = Color("TripCanvas")
    /// Grouped content surface. Light white (Sketch `Backgrounds/Light/Primary`), Dark #1C1C1E.
    static let surface = Color("ItinerarySurface")
    /// Brand fill behind white content. Sketch `Brand/Blue/500` (#356AE6) in both appearances.
    static let brand = Color("ItineraryBlue")
    /// Splash gradient stops from the brand splash video: teal top (#86E6E1),
    /// sky middle (#3F9DEB) and deep blue bottom (#315CD9).
    static let splashTop = Color("SplashGradientTop")
    static let splashMiddle = Color("SplashGradientMiddle")
    static let splashBottom = Color("SplashGradientBottom")
    /// Light blue-white for the splash tagline (#DBEEFE).
    static let splashTagline = Color("SplashTagline")
    /// Deep blue (#1B3A9C) for the soft shadow under the splash wordmark; apply with opacity.
    static let splashShadow = Color("SplashShadow")
    /// Lower endpoint for brand gradients; keeps white text readable.
    static let brandGradientEnd = Color("ItineraryBlueEnd")
    /// Brand-colored text and icons. #356AE6 in Light, #8FB0FF in Dark for contrast.
    static let accent = Color("ItineraryAction")
    /// Unselected chip and control fill. Sketch `Fills/Light/3 Tertiary` (#767680 at 12% opacity);
    /// the system role switches to its Dark variant automatically.
    static let tertiaryFill = Color(uiColor: .tertiarySystemFill)
    /// Cards on a white sheet. Sketch `Backgrounds/Light/Secondary` (#F2F2F7); Dark #1C1C1E.
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    /// Text and symbols placed on `brand` fills.
    static let onBrand = Color.white
    /// Primary label color.
    static let primaryText = Color.primary
    /// Supporting label color.
    static let secondaryText = Color.secondary
}
