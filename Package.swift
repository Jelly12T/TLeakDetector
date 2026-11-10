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
        // Objects and strong references as a graph, shortest cycle search. Knows nothing about leaks or UIKit.
        .target(name: "LeakGraph", swiftSettings: leakSettings),
        // Strong references of live objects: Swift fields and closures, ObjC ivars, collections, associated objects.
        .target(name: "LeakHeap", dependencies: ["LeakGraph"], swiftSettings: leakSettings),
        // Tasks the app starts, hooked at creation: which one holds a screen, which one outlives it.
        .target(name: "LeakConcurrency", dependencies: ["LeakCore", "LeakHeap", "LeakGraph"], swiftSettings: leakSettings),
        // Classic patterns: what Timer, CADisplayLink, NotificationCenter, URLSession and WKUserContentController
        // hold, seen by hooking their creating methods; early warnings when a screen closes.
        .target(name: "LeakPatterns", dependencies: ["LeakCore", "LeakHeap", "LeakGraph"], swiftSettings: leakSettings),
        // Decides whether something leaked. Knows nothing about UIKit.
        .target(name: "LeakCore", dependencies: ["LeakGraph"], swiftSettings: leakSettings),
        // Hooks into UIViewController and reports to LeakCore. One-way dependency.
        .target(name: "LeakUIKit", dependencies: ["LeakCore", "LeakHeap", "LeakConcurrency", "LeakPatterns"], swiftSettings: leakSettings),
        .testTarget(name: "LeakGraphTests", dependencies: ["LeakGraph"], swiftSettings: leakSettings),
        // Objective-C classes and blocks for LeakHeapTests: ivar layouts and block layouts come from clang.
        .target(name: "LeakHeapFixtures", path: "Tests/LeakHeapFixtures"),
        .testTarget(name: "LeakHeapTests", dependencies: ["LeakHeap", "LeakHeapFixtures"], swiftSettings: leakSettings),
        .testTarget(name: "LeakCoreTests", dependencies: ["LeakCore"], swiftSettings: leakSettings),
        .testTarget(name: "LeakConcurrencyTests", dependencies: ["LeakConcurrency", "LeakCore", "LeakHeap", "LeakGraph"],
                    swiftSettings: leakSettings),
        .testTarget(name: "LeakPatternsTests", dependencies: ["LeakPatterns", "LeakCore", "LeakHeap", "LeakGraph"],
                    swiftSettings: leakSettings),
        // UIKit parts; runs on an iOS simulator (empty on macOS).
        .testTarget(name: "LeakUIKitTests", dependencies: ["LeakUIKit", "LeakCore"], swiftSettings: leakSettings),
    ]
)
