//
//  LeakReporter.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import os

public enum LeakReportMode: String, Sendable {
    case crash
    case debugger
    case log
}

package enum LeakLog {
    package static let subsystem = "TLeakDetector"
    package static let leaks = Logger(subsystem: subsystem, category: "leak")
    package static let marks = Logger(subsystem: subsystem, category: "mark")
    package static let config = Logger(subsystem: subsystem, category: "config")
}

/// Shows each leak signature once per run: logs it, then stops in the debugger or crashes,
/// unless a suppression still covers it.
@MainActor
package final class LeakReporter {
    package struct Effects {
        package var log: @MainActor (OSLogType, String) -> Void
        package var now: @MainActor () -> Date
        package var isDebuggerAttached: @MainActor () -> Bool
        package var breakIntoDebugger: @MainActor () -> Void
        package var crash: @MainActor (String) -> Void

        package init(
            log: @escaping @MainActor (OSLogType, String) -> Void,
            now: @escaping @MainActor () -> Date,
            isDebuggerAttached: @escaping @MainActor () -> Bool,
            breakIntoDebugger: @escaping @MainActor () -> Void,
            crash: @escaping @MainActor (String) -> Void
        ) {
            self.log = log
            self.now = now
            self.isDebuggerAttached = isDebuggerAttached
            self.breakIntoDebugger = breakIntoDebugger
            self.crash = crash
        }

        package static var live: Effects {
            Effects(
                log: { LeakLog.leaks.log(level: $0, "\($1, privacy: .public)") },
                now: { Date() },
                isDebuggerAttached: LeakReporter.isDebuggerAttached,
                breakIntoDebugger: { _ = raise(SIGTRAP) },
                crash: { assertionFailure($0) })
        }
    }

    /// `nil`: stop in the debugger if one is attached, crash otherwise.
    private let mode: LeakReportMode?
    private let suppressions: [LeakSuppression]
    private let effects: Effects
    private var reported: Set<LeakSignature> = []

    package init(mode: LeakReportMode? = nil, suppressions: [LeakSuppression] = [], effects: Effects = .live) {
        self.mode = mode
        self.suppressions = suppressions
        self.effects = effects
    }

    package func report(_ report: LeakReport) {
        guard reported.insert(report.signature).inserted else { return }
        var message = report.description
        if let suppression = suppressions.first(where: { $0.signature == report.signature }) {
            let note = "\(suppression.reason) (owner: \(suppression.owner))"
            guard effects.now() >= suppression.endsAt else {
                effects.log(.default, message + "\n  suppressed until \(suppression.expires): \(note)")
                return
            }
            message += "\n  suppression expired on \(suppression.expires): \(note)"
        }
        // Resolved per report: a debugger can be attached after launch.
        switch mode ?? (effects.isDebuggerAttached() ? .debugger : .crash) {
        case .log:
            effects.log(.error, message)
        case .debugger:
            effects.log(.error, message + "\n  Paused by TLeakDetector. Continue to resume.")
            effects.breakIntoDebugger()
        case .crash:
            effects.log(.error, message)
            effects.crash(message)
        }
    }

    nonisolated package static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}

#endif
