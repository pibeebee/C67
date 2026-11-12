// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "C67Backend",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "C67Domain", targets: ["C67Domain"]),
        .library(name: "C67Data", targets: ["C67Data"])
    ],
    dependencies: [.package(path: "../packages/PocketEngine")],
    targets: [
        .target(name: "C67Domain", path: "Sources/Domain"),
        .target(name: "C67Data", dependencies: ["C67Domain", .product(name: "PocketEngine", package: "PocketEngine")], path: "Sources/Data",
                resources: [.copy("Fixtures/rundowns.json"), .copy("Fixtures/planning-input.json"),
                            .copy("Fixtures/planning-result.json"), .copy("Fixtures/planning-job.json"),
                            .copy("Fixtures/personal-planning-trip.json")]),
        .testTarget(name: "C67BackendTests", dependencies: ["C67Domain", "C67Data", .product(name: "PocketEngine", package: "PocketEngine")], path: "Tests/Starter")
    ]
)
