// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PocketEngine",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "PocketEngine", targets: ["PocketEngine"])],
    targets: [
        .target(name: "PocketEngine", resources: [.process("Resources")]),
        .testTarget(name: "PocketEngineTests", dependencies: ["PocketEngine"])
    ],
    swiftLanguageModes: [.v6]
)
