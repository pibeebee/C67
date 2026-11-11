import SwiftUI
import Testing
import UIKit
@testable import C67

@MainActor
@Suite("Splash and location permission match Sketch HI-FI")
struct SplashAndLocationPermissionTests {
    @Test("Splash gradient colors are bundled", arguments: [
        "SplashGradientTop", "SplashGradientMiddle", "SplashGradientBottom", "SplashTagline", "SplashShadow",
    ])
    func splashColorExists(name: String) {
        #expect(UIColor(named: name) != nil)
    }

    @Test("Figma logo exports are bundled", arguments: [
        TravelantMarkAssets.route, TravelantMarkAssets.leadingAntenna, TravelantMarkAssets.trailingAntenna,
    ].map(\.name) + ["SplashBall"])
    func figmaAssetExists(name: String) {
        #expect(UIImage(named: name) != nil)
    }

    @Test("Native launch screen starts on the splash color without a logo, like the video's first frame")
    func launchScreenConfiguration() throws {
        let launch = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        #expect(launch["UIColorName"] as? String == "SplashGradientMiddle")
        #expect(launch["UIImageName"] == nil)
    }

    @Test("The permission alert shows the Sketch app name and explanation")
    func locationPermissionCopy() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Travelant")
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
                == "Your location is used to get your position on the map to improve the best itinerary for you"
        )
    }

    @Test("Splash renders at the Sketch frame size")
    func splashRenders() throws {
        let renderer = ImageRenderer(
            content: SplashFrameView(frame: SplashTimeline.finalFrame).frame(width: 402, height: 874)
        )
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        #expect(image.size == CGSize(width: 402, height: 874))
    }

    @Test("The location pill changes while locating")
    func locatingPillRendersDifferently() throws {
        func png(_ isLocating: Bool) throws -> Data {
            let renderer = ImageRenderer(
                content: TripLocationButton(title: "Current device position", isLocating: isLocating, action: {})
                    .frame(width: 260, height: 44)
            )
            renderer.scale = 1
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try png(true) != png(false))
    }
}
