// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TripIntegration",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "TripIntegration", targets: ["TripIntegration"]),
               .executable(name: "p3-mapkit-probe", targets: ["MapKitProbe"])],
    dependencies: [
        .package(path: "../../../c67-foundation-lab/Packages/PreferenceQuality"),
        .package(path: "../../../c67-foundation-lab/Packages/VisitTiming"),
    ],
    targets: [
        .target(name: "TripIntegration", dependencies: [
            .product(name: "PreferenceQuality", package: "PreferenceQuality"),
            .product(name: "VisitTiming", package: "VisitTiming"),
        ], resources: [.process("Resources")]),
        .executableTarget(name: "MapKitProbe", dependencies: ["TripIntegration",
                                                              .product(name: "PreferenceQuality", package: "PreferenceQuality")]),
        .testTarget(name: "TripIntegrationTests", dependencies: [
            "TripIntegration",
            .product(name: "PreferenceQuality", package: "PreferenceQuality"),
            .product(name: "VisitTiming", package: "VisitTiming"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
