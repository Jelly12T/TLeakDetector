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
    @Test("Released screen: nothing reported. Screen kept alive by a cycle: whole subtree reported")
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
        #expect(Set(box.items.map(\.context.path)) == ["ScreenVC", "ScreenVC.view", "ScreenVC.model"])
        #expect(box.items.allSatisfy { $0.context.trigger == .dismiss && $0.context.rootTypeName == "ScreenVC" })
        withExtendedLifetime(leaked) {}
    }
}

@MainActor
private final class Reports { var items: [LeakReport] = [] }

@MainActor
private final class TestScheduler: LeakScheduler {
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
