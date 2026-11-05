//
//  LeakScheduler.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// Time source + timer for the registry. Behind a protocol so tests advance time instantly.
@MainActor
package protocol LeakScheduler {
    /// Monotonic seconds.
    var now: TimeInterval { get }
    /// Runs `action` on the main actor after `delay` seconds.
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void)
}

/// Production scheduler: main queue, uptime clock.
package struct MainQueueScheduler: LeakScheduler {
    package init() {}

    package var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    package func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
}

#endif
