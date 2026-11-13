// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "C67PocketEngineLab",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "PocketEngine", targets: ["PocketEngine"])],
    targets: [.target(name: "PocketEngine", resources: [.process("Resources")]), .testTarget(name: "PocketEngineTests", dependencies: ["PocketEngine"])],
    swiftLanguageModes: [.v6]
)
