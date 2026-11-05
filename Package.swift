// swift-tools-version: 6.0
import PackageDescription

/// Every target gets this flag, and only in the debug configuration.
/// All source is wrapped in `#if LEAK_DETECTOR_ENABLED`, so in release the
/// modules still compile but are empty. See docs/adr/001-exclude-from-release.md.
let leakSettings: [SwiftSetting] = [
    .define("LEAK_DETECTOR_ENABLED", .when(configuration: .debug)),
]

let package = Package(
    name: "TLeakDetector",
    platforms: [
        // Must match the minimum iOS of the host app.
        .iOS(.v15),
        // Only so LeakCore (no UIKit) builds and tests on a Mac / CI.
        .macOS(.v13),
    ],
    products: [
        // Single product: the app adds one dependency only.
        .library(name: "TLeakDetector", targets: ["LeakUIKit", "LeakCore"]),
    ],
    targets: [
        // Decides whether something leaked. Knows nothing about UIKit.
        .target(name: "LeakCore", swiftSettings: leakSettings),
        // Hooks into UIViewController and reports to LeakCore. One-way dependency.
        .target(name: "LeakUIKit", dependencies: ["LeakCore"], swiftSettings: leakSettings),
        .testTarget(name: "LeakCoreTests", dependencies: ["LeakCore"], swiftSettings: leakSettings),
        // UIKit parts; runs on an iOS simulator (empty on macOS).
        .testTarget(name: "LeakUIKitTests", dependencies: ["LeakUIKit", "LeakCore"], swiftSettings: leakSettings),
    ]
)
