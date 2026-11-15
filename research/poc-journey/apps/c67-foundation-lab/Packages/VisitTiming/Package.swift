// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VisitTiming",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VisitTiming", targets: ["VisitTiming"]),
        .executable(name: "visit-time-eval", targets: ["VisitTimeEval"]),
    ],
    targets: [
        .target(name: "VisitTiming", resources: [.process("Resources")]),
        .executableTarget(name: "VisitTimeEval", dependencies: ["VisitTiming"]),
        .testTarget(name: "VisitTimingTests", dependencies: ["VisitTiming"], resources: [.copy("Fixtures")]),
    ]
)
