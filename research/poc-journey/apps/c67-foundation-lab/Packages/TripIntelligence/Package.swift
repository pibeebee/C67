// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TripIntelligence",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TripIntelligence", targets: ["TripIntelligence"]),
        .executable(name: "fm-trip-eval", targets: ["FMTripEval"]),
    ],
    targets: [
        .target(name: "TripIntelligence", resources: [.process("Resources")]),
        .executableTarget(name: "FMTripEval", dependencies: ["TripIntelligence"]),
        .testTarget(name: "TripIntelligenceTests", dependencies: ["TripIntelligence"]),
    ]
)
