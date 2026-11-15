// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PreferenceQuality",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PreferenceQuality", targets: ["PreferenceQuality"]),
        .executable(name: "preference-quality-eval", targets: ["QualityEval"]),
        .executable(name: "embedding-benefit-eval", targets: ["BenefitEval"]),
    ],
    dependencies: [.package(path: "../PreferenceLearning")],
    targets: [
        .target(name: "PreferenceQuality", dependencies: ["PreferenceLearning"],
                resources: [.process("Resources")]),
        .executableTarget(name: "QualityEval", dependencies: ["PreferenceQuality"]),
        .executableTarget(name: "BenefitEval", dependencies: ["PreferenceQuality"]),
        .testTarget(name: "PreferenceQualityTests", dependencies: ["PreferenceQuality"]),
    ]
)
