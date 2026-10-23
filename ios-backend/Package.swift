// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "C67Backend",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "C67Domain", targets: ["C67Domain"]),
        .library(name: "C67Data", targets: ["C67Data"])
    ],
    targets: [
        .target(name: "C67Domain", path: "Sources/Domain"),
        .target(name: "C67Data", dependencies: ["C67Domain"], path: "Sources/Data",
                resources: [.copy("Fixtures/rundowns.json")]),
        .testTarget(name: "C67BackendTests", dependencies: ["C67Domain", "C67Data"], path: "Tests/Starter")
    ]
)
