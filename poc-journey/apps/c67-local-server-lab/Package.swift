// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "C67LocalServerLab", platforms: [.macOS(.v26), .iOS(.v26)], products: [
    .library(name: "PlannerEngine", targets: ["PlannerEngine"]),
    .library(name: "PlannerContracts", targets: ["PlannerContracts"]),
    .library(name: "PlaceContextEngine", targets: ["PlaceContextEngine"]),
    .library(name: "DynamicTripContracts", targets: ["DynamicTripContracts"]),
    .library(name: "RecommendationContracts", targets: ["RecommendationContracts"]),
    .executable(name: "places-context", targets: ["PlacesContextCLI"]),
    .executable(name: "context-pilot", targets: ["ContextPilotCLI"]),
    .executable(name: "planner-server", targets: ["PlannerServer"]),
    .executable(name: "planner-bench", targets: ["PlannerBenchCLI"])
], dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.3"),
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0"),
    .package(path: "../c67-foundation-lab/Packages/PreferenceQuality"),
    .package(path: "../c67-foundation-lab/Packages/VisitTiming"),
    .package(path: "../c67-foundation-lab/Packages/PreferenceLearning"),
    .package(path: "../c67-trip-integration/Packages/TripIntegration")
], targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.brew(["sqlite3"])]),
    .target(name: "PlaceContextEngine"),
    .target(name: "RecommendationContracts", dependencies: ["PlaceContextEngine"]),
    .target(name: "RecommendationEngine", dependencies: ["RecommendationContracts", "DynamicTripContracts", "PlaceContextEngine", "PlannerEngine"]),
    .testTarget(name: "RecommendationTests", dependencies: ["RecommendationEngine", "RecommendationContracts", "DynamicTripEngine", "DynamicTripContracts"]),
    .target(name: "DynamicTripContracts", dependencies: ["PlaceContextEngine"]),
    .target(name: "DynamicTripEngine", dependencies: ["DynamicTripContracts", "ContextPilotAdapters", "PlannerEngine"]),
    .testTarget(name: "DynamicTripTests", dependencies: ["DynamicTripEngine", "DynamicTripContracts"]),
    .target(name: "ContextPilotAdapters", dependencies: ["PlaceContextEngine", "PlannerEngine"]),
    .executableTarget(name: "ContextPilotCLI", dependencies: ["ContextPilotAdapters", "PlaceContextEngine", "PlannerEngine"]),
    .testTarget(name: "ContextPilotTests", dependencies: ["ContextPilotAdapters", "PlaceContextEngine", "PlannerEngine"]),
    .executableTarget(name: "PlacesContextCLI", dependencies: ["PlaceContextEngine"]),
    .testTarget(name: "PlaceContextEngineTests", dependencies: ["PlaceContextEngine"]),
    .target(name: "PlannerEngine", dependencies: [
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "PreferenceQuality", package: "PreferenceQuality"),
        .product(name: "PreferenceLearning", package: "PreferenceLearning"),
        .product(name: "VisitTiming", package: "VisitTiming")
    ], resources: [.process("Resources/quality.json"), .process("Resources/timing.json"), .copy("Resources/Model")]),
    .target(name: "PlannerContracts", dependencies: ["PlannerEngine"]),
    .target(name: "PlannerStorage", dependencies: ["PlannerContracts", "CSQLite"]),
    .executableTarget(name: "PlannerServer", dependencies: ["PlannerStorage", "PlaceContextEngine", "DynamicTripEngine", "RecommendationEngine", .product(name: "Vapor", package: "vapor")]),
    .executableTarget(name: "PlannerBenchCLI", dependencies: ["PlannerContracts", .product(name: "TripIntegration", package: "TripIntegration")]),
    .testTarget(name: "PlannerLabTests", dependencies: ["PlannerStorage", .product(name: "TripIntegration", package: "TripIntegration")])
], swiftLanguageModes: [.v6])
