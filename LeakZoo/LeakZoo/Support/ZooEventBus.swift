//
//  ZooEventBus.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import Foundation

/// App-wide event stream, used by Z09 and Z12. Being a singleton, it is a real
/// root: a stream it hands out stays alive until the consumer cancels.
final class ZooEventBus: @unchecked Sendable {
    static let shared = ZooEventBus()

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    /// Never finishes on its own.
    func events() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.continuations[id] = nil; self.lock.unlock()
            }
        }
    }

    func send(_ value: Int) {
        lock.lock(); let all = Array(continuations.values); lock.unlock()
        all.forEach { $0.yield(value) }
    }
}
