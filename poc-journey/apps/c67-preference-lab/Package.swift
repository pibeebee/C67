// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "C67PreferenceLab", platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "PreferenceCore", targets: ["PreferenceCore"]),
               .executable(name: "preference-bench", targets: ["PreferenceBench"])],
    targets: [.target(name: "PreferenceCore", resources: [.process("Resources")]),
              .executableTarget(name: "PreferenceBench", dependencies: ["PreferenceCore"]),
              .testTarget(name: "PreferenceCoreTests", dependencies: ["PreferenceCore"])])
