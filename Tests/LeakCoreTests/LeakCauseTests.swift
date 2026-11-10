//
//  LeakCauseTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import Testing
import LeakGraph
@testable import LeakCore

private func node(_ id: UInt, _ kind: RetainGraph.Node.Kind) -> RetainGraph.Node {
    RetainGraph.Node(id: id, kind: kind)
}

private let screen = node(1, .object(type: "ProfileVC", module: "App"))
private let model = node(2, .object(type: "ProfileModel", module: "App"))
private let closure = node(3, .closure(function: "closure #1 in ProfileVC.viewDidLoad()"))
private let task = node(4, .task(function: "closure #1 in ProfileVC.viewDidLoad()"))

private func report(_ cause: LeakCause, root: Bool = true) -> LeakReport {
    var report = LeakReport(
        kind: root ? .screen : .outlived,
        leaked: .init(typeName: root ? "ProfileVC" : "Task", path: "ProfileVC", address: 0xbeef),
        alsoAlive: [],
        context: LeakContext(trigger: .pop, rootTypeName: "ProfileVC"),
        markedAt: 10,
        detectedAt: 18)
    report.cause = cause
    return report
}

@Suite("Causes and fixes")
struct LeakCauseTests {
    @Test("A cycle through a closure: capture self weakly in that closure")
    func closureCycle() {
        let chain = RetainChain(nodes: [screen, model, closure], paths: ["model", "onChange", RetainPath([.capture(0)])],
                                certainties: [true, true, true])
        let text = report(.cycle(chain)).description
        #expect(text.contains("    ProfileModel.onChange → closure #1 in ProfileVC.viewDidLoad()"))
        #expect(text.contains("  fix: capture self weakly in closure #1 in ProfileVC.viewDidLoad(): `{ [weak self] in … }`"))
    }

    @Test("A cycle through a strong delegate: declare it weak")
    func delegateCycle() {
        let chain = RetainChain(nodes: [screen, model], paths: ["model", "delegate"], certainties: [true, true])
        #expect(LeakFixes.suggestions(for: .cycle(chain)) == ["declare `ProfileModel.delegate` as `weak var` (and its protocol as `AnyObject`)"])
    }

    @Test("Held by a running task: the chain from the task, how to cancel it, and the closure to fix")
    func heldByTask() {
        let holder = LeakHolder(.task, detail: "closure #1 in ProfileVC.viewDidLoad()")
        let chain = RetainChain(nodes: [task], paths: [RetainPath([.field("operation"), .closure(function: "closure #1 in ProfileVC.viewDidLoad()")])],
                                certainties: [true], end: screen)
        let leak = report(.heldBy(holder, chain))
        let lines = leak.description.split(separator: "\n").map(String.init)
        #expect(lines.contains("  held by a running Task (closure #1 in ProfileVC.viewDidLoad()):"))
        #expect(lines.contains("    Task.operation {closure #1 in ProfileVC.viewDidLoad()} → ProfileVC"))
        #expect(lines.contains { $0.hasPrefix("  fix: cancel the task when the screen closes") })
        #expect(lines.contains { $0.hasPrefix("  fix: capture self weakly in closure #1 in ProfileVC.viewDidLoad()") })
        #expect(leak.signature.cycle == "Task.operation {closure #1 in ProfileVC.viewDidLoad()} → ProfileVC")
    }

    @Test("A holder that is the object itself: no steps, no shape in the signature")
    func heldDirectly() {
        let token = node(5, .object(type: "__NSObserver", module: "Foundation"))
        let holder = LeakHolder(.notificationObserver, detail: "UIApplicationDidBecomeActiveNotification")
        let leak = report(.heldBy(holder, RetainChain(nodes: [], paths: [], certainties: [], end: token)), root: false)
        #expect(leak.description.contains("  held by a NotificationCenter observer for UIApplicationDidBecomeActiveNotification, never removed\n"))
        #expect(leak.description.contains("  fix: remove the observer when the screen closes"))
        #expect(leak.signature.cycle == nil)
    }

    @Test("A task still running after its screen closed")
    func running() {
        let leak = report(.running(LeakHolder(.task, detail: "closure #1 in ProfileVC.viewDidLoad()")), root: false)
        #expect(leak.description.contains("  Task (closure #1 in ProfileVC.viewDidLoad()) is still running 8.0s after ProfileVC closed"))
        #expect(leak.description.contains("continuation calls `finish()`"))
    }

    @Test("Closures named after a system image give no fix of their own")
    func systemClosure() {
        let system = node(6, .closure(function: "closure in UIKitCore"))
        let chain = RetainChain(nodes: [screen, system], paths: ["action", RetainPath([.capture(0)])], certainties: [true, true])
        #expect(LeakFixes.suggestions(for: .cycle(chain)) == ["make one reference of the cycle weak, or clear it when the screen closes"])
    }
}

@MainActor
@Suite("Warnings")
struct LeakWarningTests {
    private func warning(_ pattern: LeakPattern = .strongDelegate, _ detail: String = "Worker.delegate holds ProfileVC strongly") -> LeakWarning {
        LeakWarning(pattern: pattern, typeName: "Worker", detail: detail, fix: "declare it weak",
                    context: LeakContext(trigger: .pop, rootTypeName: "ProfileVC"))
    }

    @Test("Logged once per pattern and place, never pausing; ignored patterns not at all")
    func once() {
        var warned: [String] = []
        var stopped = false
        let effects = LeakReporter.Effects(log: { _, _ in }, now: { Date() }, isDebuggerAttached: { true },
                                           breakIntoDebugger: { stopped = true }, crash: { _ in stopped = true },
                                           warn: { warned.append($0) })
        let reporter = LeakReporter(ignoredPatterns: [.timerTarget], effects: effects)
        reporter.warn(warning())
        reporter.warn(warning())
        reporter.warn(warning(.strongDelegate, "Other.delegate holds ProfileVC strongly"))
        reporter.warn(warning(.timerTarget, "a scheduled Timer targets ProfileVC"))
        #expect(warned.count == 2)
        #expect(!stopped)
        #expect(warned.first == """
            [TLeakDetector] WARNING strongDelegate: Worker.delegate holds ProfileVC strongly
              seen when ProfileVC closed (pop): it leaks unless something releases it later
              fix: declare it weak
            """)
    }
}

#endif
