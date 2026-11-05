//
//  LeakRegistry.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// The heart of the tool: receives "this object must die", waits, checks, decides.
///
///     mark ──T1──► dead?      → done
///                  attached?  → cancel
///                  else       → wait for T2   (MVP has no graph, so T1 is never conclusive)
///          ──T2──► dead?      → done
///                  attached?  → cancel
///                  else       → report leak
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

    /// One expectation per object. Keyed by address, but always re-checked against the weak
    /// reference: an address can be reused once the previous object is gone.
    private var expectations: [ObjectIdentifier: LeakExpectation] = [:]
    private var nextToken: UInt64 = 0

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

    /// Marks `object` as "must die". Marking the same object again restarts its timers.
    package func expectDeallocation(of object: AnyObject, context: LeakContext) {
        let id = ObjectIdentifier(object)
        let token = makeToken()
        if let existing = expectations[id], existing.object === object {
            existing.restart(context: context, markedAt: scheduler.now, token: token)
        } else {
            // New object, or a dead one whose address got reused.
            expectations[id] = LeakExpectation(object: object, context: context, markedAt: scheduler.now, token: token)
        }
        schedule(id: id, token: token, after: configuration.t1, stage: .waitingT1)
    }

    // MARK: - Timers

    private func makeToken() -> UInt64 {
        nextToken += 1
        return nextToken
    }

    private func schedule(id: ObjectIdentifier, token: UInt64, after delay: TimeInterval, stage: LeakExpectation.Stage) {
        scheduler.schedule(after: delay) { [weak self] in
            self?.check(id: id, token: token, stage: stage)
        }
    }

    private func check(id: ObjectIdentifier, token: UInt64, stage: LeakExpectation.Stage) {
        // A newer mark (or a newer object at this address) owns the expectation now.
        guard let expectation = expectations[id], expectation.token == token else { return }

        guard let object = expectation.object else {
            expectations[id] = nil          // died: all good
            return
        }
        if attachment.isAttached(object) {
            expectations[id] = nil          // back in the hierarchy: not expected to die anymore
            return
        }

        switch stage {
        case .waitingT1:
            let next = makeToken()
            expectation.advance(to: .waitingT2, token: next)
            schedule(id: id, token: next, after: configuration.t2 - configuration.t1, stage: .waitingT2)
        case .waitingT2:
            expectations[id] = nil
            onLeak(LeakReport(
                typeName: expectation.typeName,
                context: expectation.context,
                markedAt: expectation.markedAt,
                detectedAt: scheduler.now))
        }
    }
}

#endif
