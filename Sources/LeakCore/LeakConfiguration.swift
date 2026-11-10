//
//  LeakConfiguration.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// Conforming types are never marked, and nothing they hold is walked.
/// The protocol does not exist in Release: put conformances inside `#if DEBUG`.
public protocol LeakOptOut: AnyObject {}

/// At most `max` instances of `type`, subclasses included, alive at the same time.
public struct LeakInstanceBudget {
    public let type: AnyClass
    public let max: Int

    public init(_ type: AnyClass, max: Int) {
        precondition(max >= 0, "an instance budget cannot be negative")
        self.type = type
        self.max = max
    }
}

/// Retain cycle search at T1. A certain cycle is reported at once; otherwise the cause found
/// (a possible cycle, no cycle, or a limit) is added to the report at T2.
public struct LeakGraphOptions {
    public var isEnabled: Bool
    /// The longest cycle looked for.
    public var maxDepth: Int
    /// The most objects visited per search.
    public var maxNodes: Int
    /// Seconds per search, all slices together.
    public var maxDuration: TimeInterval
    /// The search runs on the main thread a slice at a time, so no frame waits for it longer than this.
    public var sliceDuration: TimeInterval
    /// Modules whose objects are visited but not followed, e.g. `["UIKitCore"]` to stay out of UIKit internals.
    public var prunedModules: Set<String>
    /// Where each report's graph is written as DOT and JSON. `nil`: not written.
    public var exportDirectory: URL?

    public static var defaultExportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TLeakDetector", isDirectory: true)
    }

    public init(
        isEnabled: Bool = true,
        maxDepth: Int = 16,
        maxNodes: Int = 1_000,
        maxDuration: TimeInterval = 0.1,
        sliceDuration: TimeInterval = 0.004,
        prunedModules: Set<String> = [],
        exportDirectory: URL? = LeakGraphOptions.defaultExportDirectory
    ) {
        self.isEnabled = isEnabled
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.maxDuration = maxDuration
        self.sliceDuration = sliceDuration
        self.prunedModules = prunedModules
        self.exportDirectory = exportDirectory
    }
}

/// What the tool watches beyond the screen itself: tasks the app starts, and the system objects that
/// classically keep a screen alive (Timer, CADisplayLink, NotificationCenter, URLSession, WKUserContentController).
/// They tell who holds a leaked screen, and give early warnings when a screen closes.
public struct LeakChecks {
    /// Hooks the system objects above when `install()` runs. Objects made before that are not seen.
    public var isEnabled: Bool
    /// Warnings not to log.
    public var ignoredPatterns: Set<LeakPattern>
    /// Sees every task the app starts from then on: a task still running after its screen closed is reported.
    public var tracksTasks: Bool

    public init(isEnabled: Bool = true, ignoredPatterns: Set<LeakPattern> = [], tracksTasks: Bool = true) {
        self.isEnabled = isEnabled
        self.ignoredPatterns = ignoredPatterns
        self.tracksTasks = tracksTasks
    }
}

public struct LeakConfiguration {
    /// Seconds after leaving the screen of the first check.
    public var t1: TimeInterval
    /// Seconds after leaving the screen of the report.
    public var t2: TimeInterval
    /// `nil`: stop in the debugger if one is attached, crash otherwise. `TLEAK_MODE` overrides it.
    public var mode: LeakReportMode?
    /// Steps below the closed screen that are marked (child, view, subview, property). `nil`: no limit.
    public var maxSubtreeDepth: Int?
    /// Allowed to outlive their screen, subclasses included, e.g. a cached view controller.
    public var allowedTypes: [AnyClass]
    /// Known leaks that are only logged until their expiry date.
    public var suppressionFile: URL?
    /// View controllers are counted at `viewDidLoad`; other types call `TLeakDetector.track(self)`.
    public var instanceBudgets: [LeakInstanceBudget]
    public var graph: LeakGraphOptions
    public var checks: LeakChecks

    public static var defaultSuppressionFile: URL? {
        Bundle.main.url(forResource: "LeakSuppressions", withExtension: "json")
    }

    public init(
        t1: TimeInterval = 2,
        t2: TimeInterval = 8,
        mode: LeakReportMode? = nil,
        maxSubtreeDepth: Int? = nil,
        allowedTypes: [AnyClass] = [],
        suppressionFile: URL? = LeakConfiguration.defaultSuppressionFile,
        instanceBudgets: [LeakInstanceBudget] = [],
        graph: LeakGraphOptions = LeakGraphOptions(),
        checks: LeakChecks = LeakChecks()
    ) {
        self.checks = checks
        self.t1 = t1
        self.t2 = t2
        self.mode = mode
        self.maxSubtreeDepth = maxSubtreeDepth
        self.allowedTypes = allowedTypes
        self.suppressionFile = suppressionFile
        self.instanceBudgets = instanceBudgets
        self.graph = graph
    }
}

extension LeakConfiguration {
    package var isExempt: @Sendable (AnyClass) -> Bool {
        let allowed = Set(allowedTypes.map { ObjectIdentifier($0) })
        return { cls in
            cls is LeakOptOut.Type || superclasses(of: cls).contains { allowed.contains(ObjectIdentifier($0)) }
        }
    }
}

/// `cls` itself, then each superclass.
func superclasses(of cls: AnyClass) -> some Sequence<AnyClass> {
    sequence(first: cls, next: { class_getSuperclass($0) })
}

#endif
