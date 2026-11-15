// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TripSenseKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "TripSenseCore", targets: ["TripSenseCore"]),
               .executable(name: "TripSenseProbe", targets: ["TripSenseProbe"])],
    targets: [.target(name: "TripSenseCore"),
              .executableTarget(name: "TripSenseProbe", dependencies: ["TripSenseCore"]),
              .testTarget(name: "TripSenseCoreTests", dependencies: ["TripSenseCore"])]
)
