// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "C67Backend",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "C67Domain", targets: ["C67Domain"]),
        .library(name: "C67Data", targets: ["C67Data"]),
        .library(name: "C67PlannerV5", targets: ["C67PlannerV5"])
    ],
    dependencies: [.package(path: "../PocketEngine")],
    targets: [
        .target(name: "C67Domain", path: "Sources/Domain"),
        .target(name: "C67Data", dependencies: ["C67Domain", "C67PlannerV5", .product(name: "PocketEngine", package: "PocketEngine")], path: "Sources/Data"),
        .target(name: "C67PlannerV5", dependencies: ["C67Domain"], path: "Sources/PlannerV5"),
        .testTarget(name: "C67BackendTests", dependencies: ["C67Domain", "C67Data", "C67PlannerV5", .product(name: "PocketEngine", package: "PocketEngine")], path: "Tests/Starter", exclude: ["V4Replay.json", "V4ExhaustiveReplay.json"])
    ]
)
