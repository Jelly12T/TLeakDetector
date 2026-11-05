// swift-tools-version: 5.9
// SPIKE CODE — reference only, never used in production. See docs/adr/002-swift-field-ownership.md.
import PackageDescription

let package = Package(
    name: "FieldOwnershipSpike",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "SpikeReport", targets: ["SpikeReport"]),
    ],
    targets: [
        // metadata → type descriptor → field descriptor → ownership
        .target(name: "FieldOwnershipReader"),
        // A Swift class in another module: field types referring to it get *indirect* symbolic refs.
        .target(name: "SpikeExternal"),
        // Sample types for the 5 questions.
        .target(name: "SpikeSamples", dependencies: ["SpikeExternal"]),
        // Runs every check and prints SPIKE| lines. Used by the tests and by SpikeHost (device).
        .target(name: "SpikeReport", dependencies: ["FieldOwnershipReader", "SpikeSamples", "SpikeExternal"]),
        .testTarget(name: "FieldOwnershipSpikeTests", dependencies: ["SpikeReport"]),
    ]
)
