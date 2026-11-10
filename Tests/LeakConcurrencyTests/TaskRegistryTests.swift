//
//  TaskRegistryTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import Testing
import LeakCore
import LeakGraph
import LeakHeap
@testable import LeakConcurrency

private final class Owner: @unchecked Sendable {
    func handle(_ value: Int) {}
}

/// A stream that never finishes until told to: what keeps a `for await` loop, and its task, alive.
private final class Feed: @unchecked Sendable {
    let stream: AsyncStream<Int>
    let continuation: AsyncStream<Int>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Int.self)
    }
}

private func installed() {
    TaskRegistry.install { $0.contains(".xctest/") }
}

private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
}

@Suite("Task registry", .serialized)
struct TaskRegistryTests {
    @Test("A task started by the app is live until it returns, named after its operation")
    func liveUntilReturn() async throws {
        installed()
        let feed = Feed(), owner = Owner()
        var task: Task<Void, Never>? = Task { [owner] in for await value in feed.stream { owner.handle(value) } }
        // A LiveTask keeps its task alive: only its address is kept here.
        let address = try #require(TaskRegistry.liveTasks().first { $0.operation.contains("liveUntilReturn") }.map {
            #expect($0.operation.hasPrefix("closure #1 in TaskRegistryTests.liveUntilReturn()"))
            return $0.address
        })
        feed.continuation.finish()
        _ = await task?.value
        task = nil
        await waitUntil { !TaskRegistry.liveTasks().contains { $0.address == address } }
        #expect(!TaskRegistry.liveTasks().contains { $0.address == address })
    }

    @Test("A finished task is not live, even while its handle is still held")
    func finishedWithHandle() async {
        installed()
        let owner = Owner()
        let task = Task { [owner] in owner.handle(1) }
        _ = await task.value
        await waitUntil { TaskRegistry.tasks(pointingTo: [owner]).isEmpty }
        #expect(TaskRegistry.tasks(pointingTo: [owner]).isEmpty)
        withExtendedLifetime(task) {}
    }

    @Test("A task holding its owner strongly or weakly is found working for it; others are not")
    func pointingTo() async {
        installed()
        let feed = Feed(), strong = Owner(), weak = Owner(), other = Owner()
        let first = Task { [strong] in for await value in feed.stream { strong.handle(value) } }
        let second = Task { [weak weak] in for await value in feed.stream { weak?.handle(value) } }
        defer { feed.continuation.finish(); first.cancel(); second.cancel() }
        #expect(TaskRegistry.tasks(pointingTo: [strong]).count == 1)
        #expect(TaskRegistry.tasks(pointingTo: [weak]).count == 1)
        #expect(TaskRegistry.tasks(pointingTo: [other]).isEmpty)
    }

    @Test("The task's context is a root of the retain graph: its operation leads to what it captured")
    func taskRoot() async throws {
        installed()
        let feed = Feed(), owner = Owner()
        let task = Task { [owner] in for await value in feed.stream { owner.handle(value) } }
        defer { feed.continuation.finish(); task.cancel() }
        let live = try #require(TaskRegistry.tasks(pointingTo: [owner]).first)
        let search = LiveHeap().shortestChain(from: [live.root], to: [UInt(bitPattern: ObjectIdentifier(owner))])
        guard case .found(let chain) = search.outcome else { Issue.record("not found: \(search.outcome)"); return }
        #expect(chain.isCertain)
        #expect(chain.description.hasPrefix("Task.operation"))
        #expect(chain.end.name == "Owner")
    }

    @Test("A probe is alive while its task runs, dead once it returns; it does not keep the task alive")
    @MainActor
    func probe() async throws {
        installed()
        let feed = Feed(), owner = Owner()
        var task: Task<Void, Never>? = Task { [weak owner] in for await value in feed.stream { owner?.handle(value) } }
        let probe = try #require(TaskRegistry.tasks(pointingTo: [owner]).first.map(TaskProbe.init))
        #expect(probe.isAlive)
        #expect(probe.typeName == "Task")
        #expect(probe.holder.kind == .task)
        feed.continuation.finish()
        _ = await task?.value
        task = nil
        for _ in 0..<200 where probe.isAlive { try? await Task.sleep(nanoseconds: 5_000_000) }
        #expect(!probe.isAlive)
    }
}

#endif
