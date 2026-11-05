//
//  TestDoubles.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
@testable import LeakCore

/// Scheduler whose clock only moves when the test says so.
@MainActor
final class ManualScheduler: LeakScheduler {
    private(set) var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, seq: Int, action: @MainActor @Sendable () -> Void)] = []
    private var seq = 0

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        seq += 1
        pending.append((now + delay, seq, action))
    }

    /// Runs every timer due within `seconds`, in order, then sets the clock.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = pending.filter({ $0.at <= target }).min(by: { ($0.at, $0.seq) < ($1.at, $1.seq) }) {
            pending.removeAll { $0.seq == next.seq }
            now = next.at
            next.action()
        }
        now = target
    }
}

/// Attachment controlled by the test.
@MainActor
final class FakeAttachment: LeakAttachmentChecking {
    var attached: Set<ObjectIdentifier> = []
    func isAttached(_ object: AnyObject) -> Bool { attached.contains(ObjectIdentifier(object)) }
}

final class Probe {}
final class OtherProbe {}

#endif
