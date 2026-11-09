//
//  LeakRegistry.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// The heart of the tool: receives "this subtree must die", waits, checks, decides.
///
///     mark ──T1──► all dead?       → done
///                  root attached?  → cancel
///                  else            → wait for T2   (MVP has no graph, so T1 is never conclusive)
///          ──T2──► all dead?       → done
///                  root attached?  → cancel
///                  else            → one report with every object still alive
///
/// T1 and T2 are measured from the mark. Holds every object weakly.
@MainActor
package final class LeakRegistry {
    package struct Configuration: Sendable {
        package var t1: TimeInterval
        package var t2: TimeInterval

        package static let `default` = Configuration(t1: 2, t2: 8)

        package init(t1: TimeInterval, t2: TimeInterval) {
            precondition(t2 >= t1, "T2 must not be earlier than T1")
            self.t1 = t1
            self.t2 = t2
        }
    }

    private let scheduler: LeakScheduler
    private let attachment: LeakAttachmentChecking
    private let configuration: Configuration
    private let onLeak: @MainActor (LeakReport) -> Void

    /// The latest expectation of each object: marking an object again moves it to the new mark.
    /// Keyed by address, but always re-checked against the weak reference: an address can be
    /// reused once the previous object is gone.
    private var expectations: [ObjectIdentifier: LeakExpectation] = [:]
    private var marks: [UInt64: LeakMark] = [:]
    private var lastMarkID: UInt64 = 0

    package init(
        scheduler: LeakScheduler,
        attachment: LeakAttachmentChecking,
        configuration: Configuration = .default,
        onLeak: @escaping @MainActor (LeakReport) -> Void
    ) {
        self.scheduler = scheduler
        self.attachment = attachment
        self.configuration = configuration
        self.onLeak = onLeak
    }

    /// Number of objects currently being watched.
    package var pendingCount: Int { expectations.count }

    package func expectation(for object: AnyObject) -> LeakExpectation? {
        guard let existing = expectations[ObjectIdentifier(object)], existing.object === object else { return nil }
        return existing
    }

    func stage(of object: AnyObject) -> LeakMark.Stage? {
        expectation(for: object).flatMap { marks[$0.markID]?.stage }
    }

    /// Marks `members` as "must die" because `root` left. Members come root first, the report
    /// is headed by the first one still alive.
    package func expectDeallocation(
        of members: [(object: AnyObject, path: String)],
        root: AnyObject,
        context: LeakContext
    ) {
        guard !members.isEmpty else { return }
        lastMarkID += 1
        let mark = LeakMark(id: lastMarkID, root: root, context: context, markedAt: scheduler.now)
        for member in members {
            // A screen that left on its own (e.g. a sibling in a cycle) is reported by its own mark.
            if member.object !== root, let pending = expectation(for: member.object),
               marks[pending.markID]?.root === member.object {
                continue
            }
            let expectation = LeakExpectation(object: member.object, path: member.path, markID: mark.id)
            expectations[expectation.objectID] = expectation
            mark.members.append(expectation)
        }
        marks[mark.id] = mark
        schedule(mark.id, after: configuration.t1)
    }

    // MARK: - Timers

    private func schedule(_ id: UInt64, after delay: TimeInterval) {
        scheduler.schedule(after: delay) { [weak self] in
            self?.check(id)
        }
    }

    private func check(_ id: UInt64) {
        guard let mark = marks[id] else { return }
        // The screen came back: everything it holds is legitimately alive.
        let rootIsAttached = mark.root.map { attachment.isAttached($0) } ?? false

        var alive: [(expectation: LeakExpectation, object: AnyObject)] = []
        // Members marked again since belong to a newer mark.
        for member in mark.members where expectations[member.objectID] === member {
            if !rootIsAttached, let object = member.object, !attachment.isAttached(object) {
                alive.append((member, object))
            } else {
                expectations[member.objectID] = nil
            }
        }
        mark.members = alive.map(\.expectation)
        guard !alive.isEmpty else {
            marks[id] = nil
            return
        }

        switch mark.stage {
        case .waitingT1:
            mark.stage = .waitingT2
            schedule(id, after: configuration.t2 - configuration.t1)
        case .waitingT2:
            marks[id] = nil
            for member in mark.members { expectations[member.objectID] = nil }
            let objects = alive.map {
                LeakReport.Object(typeName: $0.expectation.typeName, path: $0.expectation.path,
                                  address: UInt(bitPattern: $0.expectation.objectID))
            }
            let report = LeakReport(
                kind: mark.root == nil ? .outlived : .screen,
                leaked: objects[0],
                alsoAlive: Array(objects.dropFirst()),
                context: mark.context,
                markedAt: mark.markedAt,
                detectedAt: scheduler.now)
            // Keep them alive while the debugger is paused on the report.
            withExtendedLifetime(alive) { onLeak(report) }
        }
    }
}

#endif
