//
//  HoldersEndToEndTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import Testing
import UIKit
import LeakConcurrency
import LeakPatterns
@testable import LeakCore
@testable import LeakUIKit

final class TimerScreenVC: UIViewController {
    func tick() {}
}

/// Events that never end until told to: a `for await` over it, and its task, never return.
final class EndlessEvents: @unchecked Sendable {
    let stream: AsyncStream<Int>
    let continuation: AsyncStream<Int>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream(of: Int.self) }
}

final class StreamScreenVC: UIViewController {
    func handle(_ event: Int) {}
}

@MainActor
@Suite("End to end with holders: timers, tasks", .serialized)
struct HoldersEndToEndTests {
    private let checks = LeakChecks(isEnabled: true, tracksTasks: true)

    init() {
        FrameworkHolds.shared.install()
        TaskRegistry.install { $0.contains(".xctest/") }
    }

    private func registry(_ reports: Reports, _ scheduler: TestScheduler) -> LeakRegistry {
        LeakRegistry(scheduler: scheduler, attachment: UIKitAttachmentChecker(), configuration: .init(t1: 2, t2: 8),
                     cycleSearch: TLeakDetector.cycleSearch(LeakGraphOptions(maxDuration: 1), scheduler: scheduler)) {
            reports.items.append($0)
        }
    }

    @Test("A screen a repeating timer's block keeps alive: held by the timer, from the timer to the screen")
    func heldByTimer() throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let screen = TimerScreenVC()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in screen.tick() }
        defer { timer.invalidate() }

        TLeakDetector.expectDeallocation(of: screen, trigger: .pop, in: registry, filter: testFilter, checks: checks)
        scheduler.advance(by: 8)
        let report = try #require(reports.items.first)
        guard case .heldBy(let holder, let chain) = report.cause else {
            Issue.record("not held: \(String(describing: report.cause))")
            return
        }
        #expect(holder.kind == .timer)
        #expect(chain.isCertain)
        #expect(chain.description.hasPrefix("__NSCFTimer.block → block.closure"), "\(chain)")
        #expect(chain.end.name == "TimerScreenVC")
        #expect(report.description.contains("  fix: invalidate the timer"))
    }

    @Test("A screen a running task holds strongly: held by that task, named after its operation")
    func heldByTask() async throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let events = EndlessEvents()
        let screen = StreamScreenVC()
        let task = Task { for await event in events.stream { screen.handle(event) } }
        defer { events.continuation.finish(); task.cancel() }

        TLeakDetector.expectDeallocation(of: screen, trigger: .pop, in: registry, filter: testFilter, checks: checks)
        scheduler.advance(by: 8)
        let report = try #require(reports.items.first { $0.leaked.typeName == "StreamScreenVC" })
        guard case .heldBy(let holder, let chain) = report.cause else {
            Issue.record("not held: \(String(describing: report.cause))")
            return
        }
        #expect(holder.kind == .task)
        #expect(holder.detail.contains("heldByTask()"), "\(holder)")
        #expect(chain.description.hasPrefix("Task.operation"), "\(chain)")
        #expect(chain.end.name == "StreamScreenVC")
    }

    @Test("A task capturing its screen weakly outlives it: the screen dies, the task is reported as still running")
    func taskOutlivesScreen() async throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let events = EndlessEvents()
        var screen: StreamScreenVC? = StreamScreenVC()
        let task = Task { [weak screen] in for await event in events.stream { screen?.handle(event) } }
        defer { events.continuation.finish(); task.cancel() }

        TLeakDetector.expectDeallocation(of: screen!, trigger: .pop, in: registry, filter: testFilter, checks: checks)
        screen = nil
        scheduler.advance(by: 8)
        let report = try #require(reports.items.first)
        #expect(report.kind == .outlived)
        #expect(report.leaked.typeName == "Task")
        #expect(report.leaked.path.hasPrefix("Task (closure #1 in HoldersEndToEndTests.taskOutlivesScreen()"), "\(report.leaked.path)")
        guard case .running(let holder) = report.cause else {
            Issue.record("not running: \(String(describing: report.cause))")
            return
        }
        #expect(holder.kind == .task)
    }

    @Test("A task that ends with its screen is not reported")
    func taskEndsInTime() async throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let events = EndlessEvents()
        var screen: StreamScreenVC? = StreamScreenVC()
        let task = Task { [weak screen] in for await event in events.stream { screen?.handle(event) } }

        TLeakDetector.expectDeallocation(of: screen!, trigger: .pop, in: registry, filter: testFilter, checks: checks)
        screen = nil
        events.continuation.finish()
        _ = await task.value
        scheduler.advance(by: 8)
        #expect(reports.items.isEmpty)
    }
}

#endif

