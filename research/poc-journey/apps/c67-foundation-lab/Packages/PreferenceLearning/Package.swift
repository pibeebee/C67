// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PreferenceLearning",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PreferenceLearning", targets: ["PreferenceLearning"]),
        .executable(name: "preference-eval", targets: ["PreferenceEval"]),
    ],
    dependencies: [
        .package(path: "../TripIntelligence"),
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0"),
    ],
    targets: [
        .target(
            name: "PreferenceLearning",
            dependencies: [
                .product(name: "TripIntelligence", package: "TripIntelligence"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ], resources: [.copy("Resources/Model"), .process("Resources/Catalogs")]),
        .executableTarget(name: "PreferenceEval", dependencies: ["PreferenceLearning"]),
        .testTarget(name: "PreferenceLearningTests", dependencies: ["PreferenceLearning"]),
    ]
)
