// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PocketAcceptanceBench",
    platforms: [.macOS(.v26)],
    dependencies: [.package(name: "Pocket", path: "../..")],
    targets: [.executableTarget(
        name: "AcceptanceBench",
        dependencies: [.product(name: "PocketEngine", package: "Pocket")]
    )],
    swiftLanguageModes: [.v6]
)
