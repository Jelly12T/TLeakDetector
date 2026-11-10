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
        instanceBudgets: [LeakInstanceBudget] = []
    ) {
        self.t1 = t1
        self.t2 = t2
        self.mode = mode
        self.maxSubtreeDepth = maxSubtreeDepth
        self.allowedTypes = allowedTypes
        self.suppressionFile = suppressionFile
        self.instanceBudgets = instanceBudgets
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
