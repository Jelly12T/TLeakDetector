//
//  LeakUIKitTests.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import Testing
import UIKit
@testable import LeakCore
@testable import LeakUIKit

final class ScreenModel {}
final class ScreenVC: UIViewController {
    let model = ScreenModel()
    weak var weakModel: ScreenModel?
}
final class ChildVC: UIViewController {}
final class CachedVC: UIViewController {}
final class OptedOutVC: UIViewController, LeakOptOut {}
final class BudgetedModel {}
final class BudgetedVC: UIViewController {}

private func isTestType(_ cls: AnyClass) -> Bool {
    ObjectIdentifier(cls) == ObjectIdentifier(ScreenModel.self)
}

/// Test classes live in the test bundle, not `Bundle.main`: treat everything outside UIKit as app.
func isNotUIKit(_ cls: AnyClass) -> Bool {
    Bundle(for: cls) != Bundle(for: UIViewController.self)
}

let testFilter = SubtreeFilter(viewController: isNotUIKit, property: isTestType)

private func paths(_ items: [SubtreeCollector.Item]) -> [String] { items.map(\.path) }

@MainActor
@Suite("SubtreeCollector")
struct SubtreeCollectorTests {
    @Test("Collects VC, children, view hierarchy and app-type properties")
    func collectsSubtree() {
        let screen = ScreenVC()
        let child = ChildVC()
        screen.addChild(child)
        screen.view.addSubview(child.view)
        child.didMove(toParent: screen)
        let label = UILabel()
        screen.view.addSubview(label)

        let items = SubtreeCollector.collect(from: screen, filter: testFilter)
        let all = paths(items)
        #expect(all.first == "ScreenVC")
        #expect(all.contains("ScreenVC.children[0]"))
        #expect(all.contains("ScreenVC.children[0].view"))        // child's view gets the child path
        #expect(all.contains("ScreenVC.view"))
        #expect(all.contains("ScreenVC.view.subviews[1]"))        // the label
        #expect(all.contains("ScreenVC.model"))
        #expect(Set(items.map { ObjectIdentifier($0.object) }).count == items.count)  // no duplicates
    }

    @Test("Does not load a view that was never loaded")
    func doesNotLoadView() {
        let screen = ScreenVC()
        let items = SubtreeCollector.collect(from: screen, filter: testFilter)
        #expect(!screen.isViewLoaded)
        #expect(paths(items) == ["ScreenVC", "ScreenVC.model"])
    }

    private func exemptFilter() -> SubtreeFilter {
        var filter = testFilter
        filter.exempt = LeakConfiguration(allowedTypes: [CachedVC.self], suppressionFile: nil).isExempt
        return filter
    }

    @Test("Allowlisted or opted-out root: nothing collected")
    func exemptRoot() {
        for screen in [CachedVC(), OptedOutVC()] {
            screen.loadViewIfNeeded()
            #expect(SubtreeCollector.collect(from: screen, filter: exemptFilter()).isEmpty)
        }
    }

    @Test("Exempt child: it, its view and what is below are skipped; the rest of the screen is collected")
    func exemptChild() {
        let screen = ScreenVC(), child = CachedVC()
        screen.addChild(child)
        screen.view.addSubview(child.view)
        child.didMove(toParent: screen)
        child.view.addSubview(UILabel())

        let items = SubtreeCollector.collect(from: screen, filter: exemptFilter())
        #expect(paths(items) == ["ScreenVC", "ScreenVC.view", "ScreenVC.model"])
    }

    @Test("maxDepth limits how far below the root objects are marked")
    func depthLimit() {
        let screen = ScreenVC()
        let label = UILabel()
        screen.view.addSubview(label)
        label.addSubview(UIView())

        func collected(_ depth: Int) -> [String] {
            var filter = testFilter
            filter.maxDepth = depth
            return paths(SubtreeCollector.collect(from: screen, filter: filter))
        }
        #expect(collected(0) == ["ScreenVC"])
        #expect(collected(1) == ["ScreenVC", "ScreenVC.view", "ScreenVC.model"])
        #expect(collected(2) == ["ScreenVC", "ScreenVC.view", "ScreenVC.view.subviews[0]", "ScreenVC.model"])
    }

    @Test("Weak properties are followed too (Mirror limitation, see ADR 002)")
    func weakPropertiesFollowed() {
        let screen = ScreenVC()
        let shared = ScreenModel()
        screen.weakModel = shared
        let items = SubtreeCollector.collect(from: screen, filter: testFilter)
        #expect(paths(items).contains("ScreenVC.weakModel"))
    }
}

@MainActor
@Suite("UIKitAttachmentChecker")
struct AttachmentTests {
    let checker = UIKitAttachmentChecker()

    private func window(root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.isHidden = false
        return window
    }

    @Test("Root VC and its view in a window are attached")
    func rootInWindow() {
        let root = ScreenVC()
        let w = window(root: root)
        #expect(checker.isAttached(root))
        #expect(checker.isAttached(root.view))
        withExtendedLifetime(w) {}
    }

    @Test("Non-top VC in a navigation stack is attached (parent is in a window)")
    func navigationStack() {
        let first = ScreenVC(), second = ScreenVC()
        let nav = UINavigationController(rootViewController: first)
        nav.pushViewController(second, animated: false)
        let w = window(root: nav)
        #expect(checker.isAttached(first))
        #expect(checker.isAttached(second))
        withExtendedLifetime(w) {}
    }

    @Test("Removed child and removed view are detached")
    func removedIsDetached() {
        let root = ScreenVC(), child = ChildVC()
        let w = window(root: root)
        root.addChild(child); root.view.addSubview(child.view); child.didMove(toParent: root)
        #expect(checker.isAttached(child))

        child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent()
        #expect(!checker.isAttached(child))
        #expect(!checker.isAttached(child.view))
        withExtendedLifetime(w) {}
    }

    @Test("Child of a detached parent is detached")
    func childOfDetachedParent() {
        let parent = ScreenVC(), child = ChildVC()
        parent.addChild(child)
        #expect(child.parent === parent)
        #expect(!checker.isAttached(child))
    }

    @Test("Plain objects are never attached")
    func plainObject() {
        #expect(!checker.isAttached(ScreenModel()))
    }
}

@MainActor
@Suite("End to end: VC closed → subtree marked → T1/T2")
struct EndToEndTests {
    @Test("Released screen: nothing reported. Screen kept alive by a cycle: one report for the subtree")
    func endToEnd() {
        let scheduler = TestScheduler()
        let box = Reports()
        let registry = LeakRegistry(scheduler: scheduler, attachment: UIKitAttachmentChecker(),
                                    configuration: .init(t1: 2, t2: 8)) { box.items.append($0) }

        // 1. A screen with nothing else holding it.
        do {
            let clean = ScreenVC()
            clean.loadViewIfNeeded()
            TLeakDetector.expectDeallocation(of: clean, trigger: .pop, in: registry, filter: testFilter)
        }
        scheduler.advance(by: 10)
        #expect(box.items.isEmpty)

        // 2. A screen kept alive from outside.
        let leaked = ScreenVC()
        leaked.loadViewIfNeeded()
        TLeakDetector.expectDeallocation(of: leaked, trigger: .dismiss, in: registry, filter: testFilter)
        scheduler.advance(by: 2)
        #expect(box.items.isEmpty)                         // T1 is never conclusive
        scheduler.advance(by: 6)
        #expect(box.items.count == 1)
        #expect(box.items.first?.kind == .screen)
        #expect(box.items.first?.leaked.path == "ScreenVC")
        #expect(box.items.first?.alsoAlive.map(\.path) == ["ScreenVC.view", "ScreenVC.model"])
        #expect(box.items.first?.context.trigger == .dismiss)
        #expect(box.items.first?.context.rootTypeName == "ScreenVC")
        withExtendedLifetime(leaked) {}
    }
}

@MainActor
@Suite("Instance budget hooks", .serialized)
struct InstanceBudgetHookTests {
    @Test("viewDidLoad counts each view controller once")
    func viewDidLoadCounts() {
        LeaveHooks.install()
        let recorder = LoadRecorder()
        TLeakDetector.loadHandler = { [weak recorder] in recorder?.loaded.append(ObjectIdentifier($0)) }
        defer { TLeakDetector.loadHandler = { TLeakDetector.budgets.track($0) } }

        let screen = BudgetedVC()
        screen.loadViewIfNeeded()
        screen.loadViewIfNeeded()
        #expect(recorder.loaded.filter { $0 == ObjectIdentifier(screen) }.count == 1)
    }

    @Test("Opening a budget-1 screen twice while the first is still alive is reported")
    func secondScreenOverBudget() throws {
        LeaveHooks.install()
        TLeakDetector.apply(LeakConfiguration(mode: .log, suppressionFile: nil,
                                              instanceBudgets: [.init(BudgetedVC.self, max: 1)]))
        defer { TLeakDetector.apply(LeakConfiguration(suppressionFile: nil)) }

        let first = BudgetedVC(), second = BudgetedVC()
        first.loadViewIfNeeded()
        #expect(TLeakDetector.budgets.aliveCount(of: BudgetedVC.self) == 1)
        second.loadViewIfNeeded()
        #expect(TLeakDetector.budgets.aliveCount(of: BudgetedVC.self) == 2)
        withExtendedLifetime((first, second)) {}
    }

    @Test("track(_:) from a background thread is counted on the main thread")
    func trackFromBackground() async {
        TLeakDetector.apply(LeakConfiguration(mode: .log, suppressionFile: nil,
                                              instanceBudgets: [.init(BudgetedModel.self, max: 1)]))
        defer { TLeakDetector.apply(LeakConfiguration(suppressionFile: nil)) }

        let model = BudgetedModel()
        nonisolated(unsafe) let handedOver = model
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                TLeakDetector.track(handedOver)
                done.resume()
            }
        }
        // Main-actor jobs are not ordered with main-queue blocks: wait behind the hop on the main queue itself (FIFO).
        await withCheckedContinuation { drained in DispatchQueue.main.async { drained.resume() } }
        #expect(TLeakDetector.budgets.aliveCount(of: BudgetedModel.self) == 1)
        TLeakDetector.track(model)
        #expect(TLeakDetector.budgets.aliveCount(of: BudgetedModel.self) == 1)
        withExtendedLifetime(model) {}
    }
}

@MainActor
private final class LoadRecorder { var loaded: [ObjectIdentifier] = [] }

final class ButtonScreenVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(UIButton(type: .system, primaryAction: UIAction(title: "Tap") { _ in self.tap() }))
    }
    func tap() {}
}

final class ClosureScreenVC: UIViewController {
    var onTap: (() -> Void)?
    func tap() {}
}

/// Keeps screens alive from outside, like a timer or a singleton would.
@MainActor
enum ScreenKeeper { static var screens: [UIViewController] = [] }

@MainActor
@Suite("End to end with the live retain graph")
struct RetainGraphEndToEndTests {
    private func registry(_ reports: Reports, _ scheduler: TestScheduler) -> LeakRegistry {
        LeakRegistry(scheduler: scheduler, attachment: UIKitAttachmentChecker(), configuration: .init(t1: 2, t2: 8),
                     cycleSearch: TLeakDetector.cycleSearch(LeakGraphOptions(maxDuration: 1), scheduler: scheduler)) {
            reports.items.append($0)
        }
    }

    @Test("A screen kept alive by a closure capturing self: a certain cycle, reported at T1")
    func closureCycle() throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let screen = ClosureScreenVC()
        screen.loadViewIfNeeded()
        screen.onTap = { screen.tap() }
        defer { screen.onTap = nil }

        TLeakDetector.expectDeallocation(of: screen, trigger: .pop, in: registry, filter: testFilter)
        scheduler.advance(by: 2)
        let report = try #require(reports.items.first)
        #expect(report.cause?.isCertainCycle == true)
        // Through a closure context, or with the screen itself as the context: both are compiler choices.
        let cycle = try #require(report.signature.cycle)
        #expect(cycle.hasPrefix("ClosureScreenVC.onTap") && cycle.hasSuffix("→ ClosureScreenVC"), "\(cycle)")
        #expect(cycle.contains("closure #1 in RetainGraphEndToEndTests.closureCycle()"), "\(cycle)")
    }

    @Test("A button whose action captures the screen: the cycle goes through the view's subviews, which no ivar shows")
    func buttonActionCycle() throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let screen = ButtonScreenVC()
        screen.loadViewIfNeeded()
        defer { screen.view.subviews.forEach { $0.removeFromSuperview() } }

        TLeakDetector.expectDeallocation(of: screen, trigger: .pop, in: registry, filter: testFilter)
        scheduler.advance(by: 8)
        let report = try #require(reports.items.first)
        guard case .cycle(let cycle) = report.cause else {
            Issue.record("no cycle: \(String(describing: report.cause))")
            return
        }
        #expect(cycle.description.hasPrefix("ButtonScreenVC._view → UIView.subviews[0] → UIButton"), "\(cycle)")
    }

    @Test("A screen with a loaded view kept alive from outside: no cycle through it, reported at T2")
    func heldFromOutside() throws {
        let reports = Reports(), scheduler = TestScheduler()
        let registry = registry(reports, scheduler)
        let screen = ScreenVC()
        screen.loadViewIfNeeded()
        screen.view.addSubview(UILabel())
        ScreenKeeper.screens.append(screen)
        defer { ScreenKeeper.screens.removeAll() }

        TLeakDetector.expectDeallocation(of: screen, trigger: .dismiss, in: registry, filter: testFilter)
        scheduler.advance(by: 2)
        #expect(reports.items.isEmpty)
        scheduler.advance(by: 6)
        let report = try #require(reports.items.first)
        guard case .noCycle = report.cause else {
            Issue.record("UIKit internals look like a cycle: \(String(describing: report.cause))")
            return
        }
    }
}

@MainActor
final class Reports { var items: [LeakReport] = [] }

@MainActor
final class TestScheduler: LeakScheduler {
    private(set) var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, seq: Int, action: @MainActor @Sendable () -> Void)] = []
    private var seq = 0
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        seq += 1; pending.append((now + delay, seq, action))
    }
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = pending.filter({ $0.at <= target }).min(by: { ($0.at, $0.seq) < ($1.at, $1.seq) }) {
            pending.removeAll { $0.seq == next.seq }; now = next.at; next.action()
        }
        now = target
    }
}

#endif
