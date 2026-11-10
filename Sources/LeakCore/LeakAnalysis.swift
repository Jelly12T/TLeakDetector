//
//  LeakAnalysis.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

/// Something outside the screen that keeps objects alive while it runs or stays registered.
package struct LeakHolder: Sendable, Equatable, CustomStringConvertible {
    /// Raw values may appear in logs and tooling: never rename them.
    package enum Kind: String, Sendable {
        case task
        case timer
        case displayLink
        case notificationObserver
        case urlSession
    }

    package let kind: Kind
    /// `closure #1 in ProfileVC.viewDidLoad()` for a task, the notification name for an observer.
    package let detail: String

    package init(_ kind: Kind, detail: String = "") {
        self.kind = kind
        self.detail = detail
    }

    /// `a running Task (closure #1 in ProfileVC.viewDidLoad())`.
    package var description: String {
        switch kind {
        case .task: "a running Task (\(detail))"
        case .timer: "a scheduled Timer\(detail.isEmpty ? "" : " (\(detail))"), never invalidated"
        case .displayLink: "a CADisplayLink, never invalidated"
        case .notificationObserver: "a NotificationCenter observer for \(detail), never removed"
        case .urlSession: "a URLSession, never invalidated"
        }
    }

    /// The holder as the subject of a sentence: `Task (closure #1 in ProfileVC.viewDidLoad())`.
    package var subject: String {
        switch kind {
        case .task: "Task (\(detail))"
        case .timer: "Timer"
        case .displayLink: "CADisplayLink"
        case .notificationObserver: "NotificationCenter observer for \(detail)"
        case .urlSession: "URLSession"
        }
    }
}

/// Why the object is still alive, found at T1. Not part of `kind` (ADR 003).
package enum LeakCause: Sendable, Equatable {
    /// A cycle of strong references through the object. Certain only if every reference is known strong.
    case cycle(RetainChain)
    /// A holder outside the screen (a running task, a timer…) reaches the object. The chain starts at the
    /// holder and ends at the object; it has no step when the holder is the object itself.
    case heldBy(LeakHolder, RetainChain)
    /// The object is a task that has not returned.
    case running(LeakHolder)
    /// No cycle through it among the objects searched: something outside the screen holds it. Unless some
    /// objects were only partly read: a cycle through one of them may have been missed.
    case noCycle(searched: Int, partlyRead: Int)
    /// The search stopped at a limit before it could tell.
    case unknown(RetainCycleSearch.Limit, searched: Int)

    package init(_ search: RetainCycleSearch) {
        let searched = search.explored.nodes.count
        switch search.outcome {
        case .found(let cycle): self = .cycle(cycle)
        case .notFound: self = .noCycle(searched: searched, partlyRead: search.partlyRead)
        case .inconclusive(let limit): self = .unknown(limit, searched: searched)
        }
    }

    package var isCertainCycle: Bool {
        if case .cycle(let cycle) = self { return cycle.isCertain }
        return false
    }

    /// The references shown in the report, and whose shape goes into the signature.
    package var chain: RetainChain? {
        switch self {
        case .cycle(let chain), .heldBy(_, let chain): chain.nodes.isEmpty ? nil : chain
        default: nil
        }
    }
}

/// What the graph says about one object: the cause, and what was searched to find it.
package struct LeakAnalysis: Sendable {
    package var cause: LeakCause
    /// For the DOT and JSON export. `nil` when nothing was searched.
    package var explored: RetainGraph?
    package var highlighted: RetainChain?

    package init(cause: LeakCause, explored: RetainGraph? = nil, highlighted: RetainChain? = nil) {
        self.cause = cause
        self.explored = explored
        self.highlighted = highlighted
    }

    package init(_ search: RetainCycleSearch) {
        self.init(cause: LeakCause(search), explored: search.explored, highlighted: search.cycle)
    }
}

/// Something that is not an object but is watched like one, e.g. a running task. Marked as a member;
/// alive while `isAlive`. Held strongly by its expectation, so it must not hold what it watches.
@MainActor
package protocol LeakProbe: AnyObject {
    var typeName: String { get }
    var isAlive: Bool { get }
}

#endif
