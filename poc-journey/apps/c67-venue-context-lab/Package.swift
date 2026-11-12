// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "C67VenueContextLab", platforms: [.macOS(.v26), .iOS(.v26)], products: [
    .library(name: "PlannerEngine", targets: ["PlannerEngine"]),
    .library(name: "PlannerContracts", targets: ["PlannerContracts"]),
    .library(name: "PlaceContextEngine", targets: ["PlaceContextEngine"]),
    .library(name: "DynamicTripContracts", targets: ["DynamicTripContracts"]),
    .library(name: "RecommendationContracts", targets: ["RecommendationContracts"]),
    .executable(name: "venue-context-server", targets: ["PlannerServer"]),
], dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.3"),
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0"),
    .package(path: "../c67-foundation-lab/Packages/PreferenceQuality"),
    .package(path: "../c67-foundation-lab/Packages/VisitTiming"),
    .package(path: "../c67-foundation-lab/Packages/PreferenceLearning"),
], targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.brew(["sqlite3"])]),
    .target(name: "PlaceContextEngine"),
    .target(name: "RecommendationContracts", dependencies: ["PlaceContextEngine"]),
    .target(name: "RecommendationEngine", dependencies: ["RecommendationContracts", "DynamicTripContracts", "PlaceContextEngine", "PlannerEngine", "VenueDiscovery"]),
    .target(name: "DynamicTripContracts", dependencies: ["PlaceContextEngine"]),
    .target(name: "DynamicTripEngine", dependencies: ["DynamicTripContracts", "ContextPilotAdapters", "PlannerEngine", "VenueDiscovery"]),
    .target(name: "ContextPilotAdapters", dependencies: ["PlaceContextEngine", "PlannerEngine"]),
    .target(name: "PlannerEngine", dependencies: [
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "PreferenceQuality", package: "PreferenceQuality"),
        .product(name: "PreferenceLearning", package: "PreferenceLearning"),
        .product(name: "VisitTiming", package: "VisitTiming")
    ], resources: [.process("Resources/quality.json"), .process("Resources/timing.json"), .copy("Resources/Model")]),
    .target(name: "VenueDiscovery", dependencies: ["PlaceContextEngine", "PlannerEngine"], resources: [.process("Resources")]),
    .testTarget(name: "VenueDiscoveryTests", dependencies: ["VenueDiscovery", "PlaceContextEngine"]),
    .target(name: "PlannerContracts", dependencies: ["PlannerEngine"]),
    .target(name: "PlannerStorage", dependencies: ["PlannerContracts", "CSQLite"]),
    .executableTarget(name: "PlannerServer", dependencies: ["PlannerStorage", "PlaceContextEngine", "DynamicTripEngine", "RecommendationEngine", "VenueDiscovery", .product(name: "Vapor", package: "vapor")]),
], swiftLanguageModes: [.v6])
