#if LEAK_DETECTOR_ENABLED

/// Core state of the detector. Platform-agnostic: no UIKit import allowed here.
@MainActor
package enum LeakCore {
    package private(set) static var isInstalled = false

    /// Marks the detector as installed. Returns `false` if it was already installed,
    /// so callers can make `install()` idempotent.
    @discardableResult
    package static func markInstalled() -> Bool {
        guard !isInstalled else { return false }
        isInstalled = true
        return true
    }

    #if DEBUG
    /// Test-only reset.
    package static func resetForTesting() {
        isInstalled = false
    }
    #endif
}

#endif
