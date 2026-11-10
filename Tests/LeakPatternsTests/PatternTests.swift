//
//  PatternTests.swift
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
@testable import LeakPatterns

private final class Screen: NSObject, URLSessionDelegate {
    @objc func tick() {}
    var worker: Worker?
    var timer: Timer?
}

private protocol WorkerDelegate: AnyObject {}
extension Screen: WorkerDelegate {}

private final class Worker {
    var delegate: WorkerDelegate?
}

private let context = LeakContext(trigger: .pop, rootTypeName: "Screen")

private func paths(_ object: AnyObject) -> [String] {
    FrameworkHolds.shared.references(of: object).map(\.path.description)
}

@Suite("Framework holds and patterns", .serialized)
@MainActor
struct PatternTests {
    init() { FrameworkHolds.shared.install() }

    @Test("A timer holds its target until invalidated: an edge, a root, and a warning when its screen closes")
    func timerTarget() throws {
        let screen = Screen()
        let timer = Timer.scheduledTimer(timeInterval: 60, target: screen, selector: #selector(Screen.tick), userInfo: nil, repeats: true)
        #expect(paths(timer) == ["target"])
        #expect(FrameworkHolds.shared.roots().contains { $0.object === timer && $0.holder.kind == .timer })
        let warnings = PatternChecker.warnings(members: [(screen, "Screen")], context: context)
        #expect(warnings.map(\.pattern) == [.timerTarget])
        #expect(warnings.first?.detail == "a scheduled Timer targets Screen (Screen)")
        timer.invalidate()
        #expect(paths(timer).isEmpty)
        #expect(PatternChecker.warnings(members: [(screen, "Screen")], context: context).isEmpty)
    }

    @Test("A block timer holds its block; the block holds the screen: a warning through the block")
    func timerBlock() {
        let screen = Screen()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in screen.tick() }
        defer { timer.invalidate() }
        #expect(paths(timer) == ["block"])
        let warnings = PatternChecker.warnings(members: [(screen, "Screen")], context: context)
        #expect(warnings.map(\.pattern) == [.timerTarget])
        #expect(warnings.first?.detail.contains("Timer's block holds Screen") == true)
    }

    @Test("An observer holds its block until removed; capturing the screen weakly is no warning")
    func observer() {
        let screen = Screen()
        let name = Notification.Name("PatternTests.observer")
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in screen.tick() }
        #expect(paths(token) == ["block"])
        #expect(FrameworkHolds.shared.roots().contains { $0.object === token && $0.holder.detail == name.rawValue })
        #expect(PatternChecker.warnings(members: [(screen, "Screen")], context: context).map(\.pattern) == [.observerBlock])
        NotificationCenter.default.removeObserver(token)
        #expect(paths(token).isEmpty)

        let weakToken = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak screen] _ in screen?.tick() }
        defer { NotificationCenter.default.removeObserver(weakToken) }
        #expect(PatternChecker.warnings(members: [(screen, "Screen")], context: context).isEmpty)
    }

    @Test("A URLSession holds its delegate until invalidated")
    func session() {
        let screen = Screen()
        let session = URLSession(configuration: .ephemeral, delegate: screen, delegateQueue: nil)
        #expect(paths(session) == ["delegate"])
        #expect(PatternChecker.warnings(members: [(screen, "Screen")], context: context).map(\.pattern) == [.urlSessionDelegate])
        session.invalidateAndCancel()
    }

    @Test("A strong delegate is a warning even when nothing leaks yet")
    func strongDelegate() {
        let screen = Screen(), worker = Worker()
        worker.delegate = screen
        let warnings = PatternChecker.warnings(members: [(worker, "Screen.worker")], context: context)
        #expect(warnings.map(\.pattern) == [.strongDelegate])
        #expect(warnings.first?.detail == "Worker.delegate holds Screen strongly")
        #expect(warnings.first?.fix.contains("weak var") == true)
    }

    @Test("Holds of system targets are not recorded: frameworks make many for themselves")
    func systemTargets() {
        let target = NSObject()
        let timer = Timer.scheduledTimer(timeInterval: 60, target: target, selector: #selector(NSObject.description as () -> String),
                                         userInfo: nil, repeats: false)
        defer { timer.invalidate() }
        #expect(paths(timer).isEmpty)
    }
}

#endif
