import Foundation

/// App-wide stream that never finishes on its own: a real root, like a socket or a store.
final class LabEndlessFeed: @unchecked Sendable {
    static let shared = LabEndlessFeed()

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    func values() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.continuations[id] = nil; self.lock.unlock()
            }
        }
    }
}
