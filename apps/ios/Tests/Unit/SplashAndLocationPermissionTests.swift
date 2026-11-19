import SwiftUI
import CoreLocation
import Testing
import UIKit
@testable import C67

@MainActor
@Suite("Splash and location permission match Sketch HI-FI")
struct SplashAndLocationPermissionTests {
    @Test("Location name uses available distinct administrative areas")
    func locationAreaName() {
        #expect(LocationAreaName.shortName("Tanah Abang, Central Jakarta") == "Tanah Abang")
        #expect(LocationAreaName.shortName("Bogor") == "Bogor")
        #expect(LocationAreaName.format(district: "Kemayoran", city: "Central Jakarta", province: "Jakarta") == "Kemayoran, Central Jakarta")
        #expect(LocationAreaName.format(district: nil, city: "Bogor", province: "West Java") == "Bogor, West Java")
        #expect(LocationAreaName.format(district: "Jakarta", city: "jakarta", province: "Jakarta") == "Jakarta")
        #expect(LocationAreaName.format(district: nil, city: " ", province: nil) == nil)
    }
    @Test("Arrival requires a recent and sufficiently accurate nearby fix")
    func arrivalFixValidation() {
        let now = Date()
        let coordinate = CLLocationCoordinate2D(latitude: -6.2, longitude: 106.8)
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        func fix(accuracy: Double, age: TimeInterval) -> CLLocation {
            CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: accuracy,
                       verticalAccuracy: 10, timestamp: now.addingTimeInterval(-age))
        }
        #expect(TripNavigation.isArrivalSample(fix(accuracy: 10, age: 1), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 100, age: 1), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 10, age: 30), target: target, now: now))
        let far = CLLocation(latitude: -6.21, longitude: 106.8)
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 10, age: 1), target: far, now: now))
    }

    @Test("Automatic arrival rejects cached samples and distant fixes with uncertain accuracy")
    func arrivalFixBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let target = CLLocation(latitude: -6.2, longitude: 106.8)
        let nearby = CLLocation(latitude: -6.20072, longitude: 106.8)
        #expect((75 ... 85).contains(nearby.distance(from: target)))

        func fix(accuracy: Double, offset: TimeInterval) -> CLLocation {
            CLLocation(coordinate: nearby.coordinate, altitude: 0, horizontalAccuracy: accuracy,
                       verticalAccuracy: 10, timestamp: now.addingTimeInterval(offset))
        }

        #expect(TripNavigation.isArrivalSample(fix(accuracy: 10, offset: -19), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 30, offset: -1), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 10, offset: -20), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: 10, offset: 20), target: target, now: now))
        #expect(!TripNavigation.isArrivalSample(fix(accuracy: -1, offset: 0), target: target, now: now))
    }

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

    @Test("Native launch screen matches the app canvas")
    func launchScreenConfiguration() throws {
        let launch = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        #expect(launch["UIColorName"] as? String == "TripCanvas")
        #expect(launch["UIImageName"] == nil)
    }

    @Test("The permission alert explains Travelants’ two location uses")
    func locationPermissionCopy() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Travelants")
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
                == "Travelants uses your location to find places near your starting point and detect arrival during an active trip."
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
                content: TripLocationLabel(title: "Current device position", isLocating: isLocating)
                    .frame(width: 260, height: 44)
            )
            renderer.scale = 1
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try png(true) != png(false))
    }
}
