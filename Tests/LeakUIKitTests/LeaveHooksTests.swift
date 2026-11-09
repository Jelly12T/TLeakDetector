//
//  LeaveHooksTests.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import Testing
import UIKit
import ObjectiveC
@testable import LeakCore
@testable import LeakUIKit

final class HookVC: UIViewController {}

final class DismissableVC: UIViewController {
    var fakeBeingDismissed = false
    override var isBeingDismissed: Bool { fakeBeingDismissed }
}
final class DismissableNav: UINavigationController {
    var fakeBeingDismissed = false
    override var isBeingDismissed: Bool { fakeBeingDismissed }
}
final class DismissableSearch: UISearchController {
    var fakeBeingDismissed = false
    override var isBeingDismissed: Bool { fakeBeingDismissed }
}

/// Other suites trigger the hooks too, so tests only look at their own objects.
@MainActor
final class LeaveRecorder {
    struct Event: Equatable {
        let id: ObjectIdentifier
        let trigger: LeakTrigger
    }
    private(set) var events: [Event] = []

    init() {
        TLeakDetector.leaveHandler = { [weak self] vc, trigger in
            self?.events.append(Event(id: ObjectIdentifier(vc), trigger: trigger))
        }
    }

    func triggers(for vc: UIViewController) -> [LeakTrigger] {
        events.filter { $0.id == ObjectIdentifier(vc) }.map(\.trigger)
    }
}

@MainActor
private func makeWindow(root: UIViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = root
    window.makeKeyAndVisible()
    return window
}

@MainActor
private func settle(_ milliseconds: Int = 150) async {
    try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
}

@MainActor
@Suite("LeaveHooks", .serialized)
struct LeaveHooksTests {
    let recorder: LeaveRecorder

    init() {
        LeaveHooks.install()
        recorder = LeaveRecorder()
    }

    @Test("Installing twice does not swap the implementations back")
    func installIsIdempotent() async {
        let selector = #selector(UIViewController.didMove(toParent:))
        let before = method_getImplementation(class_getInstanceMethod(UIViewController.self, selector)!)
        LeaveHooks.install()
        TLeakDetector.install()
        let after = method_getImplementation(class_getInstanceMethod(UIViewController.self, selector)!)
        #expect(before == after)

        let host = HookVC(), child = HookVC()
        host.addChild(child)
        child.willMove(toParent: nil)
        child.removeFromParent()
        #expect(recorder.triggers(for: child) == [.removeFromParent])
    }

    // MARK: Navigation

    @Test("pop marks the popped VC once")
    func pop() async {
        let first = HookVC(), second = HookVC()
        let nav = UINavigationController(rootViewController: first)
        let window = makeWindow(root: nav)
        nav.pushViewController(second, animated: false)
        await settle()

        nav.popViewController(animated: true)
        await settle(600)
        #expect(recorder.triggers(for: second) == [.pop])
        #expect(recorder.triggers(for: first).isEmpty)
        #expect(recorder.triggers(for: nav).isEmpty)
        withExtendedLifetime(window) {}
    }

    @Test("popToRoot marks every popped level once")
    func popToRoot() async {
        let first = HookVC(), second = HookVC(), third = HookVC()
        let nav = UINavigationController(rootViewController: first)
        let window = makeWindow(root: nav)
        nav.pushViewController(second, animated: false)
        nav.pushViewController(third, animated: false)
        await settle()

        nav.popToRootViewController(animated: true)
        await settle(600)
        #expect(recorder.triggers(for: second) == [.pop])
        #expect(recorder.triggers(for: third) == [.pop])
        #expect(recorder.triggers(for: first).isEmpty)
        withExtendedLifetime(window) {}
    }

    @Test("Interactive pop cancelled halfway: not marked. Finished: marked once")
    func interactivePop() async throws {
        let first = HookVC(), second = HookVC()
        let nav = UINavigationController(rootViewController: first)
        let transition = InteractivePop()
        nav.delegate = transition
        let window = makeWindow(root: nav)
        nav.pushViewController(second, animated: false)
        await settle()

        nav.popViewController(animated: true)
        await settle(50)
        try #require(transition.animationStarted, "interactive pop did not start")
        transition.interaction.update(0.4)
        transition.interaction.cancel()
        await settle(600)
        #expect(nav.topViewController === second)
        #expect(recorder.triggers(for: second).isEmpty)

        nav.popViewController(animated: true)
        await settle(50)
        transition.interaction.update(0.6)
        transition.interaction.finish()
        await settle(600)
        #expect(nav.topViewController === first)
        #expect(recorder.triggers(for: second) == [.pop])
        withExtendedLifetime(window) {}
    }

    // MARK: Containers

    @Test("Child removed from a custom container is marked once; the host is not")
    func removeChild() async {
        let host = HookVC(), child = HookVC()
        let window = makeWindow(root: host)
        host.addChild(child)
        host.view.addSubview(child.view)
        child.didMove(toParent: host)
        #expect(recorder.triggers(for: child).isEmpty)

        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        #expect(recorder.triggers(for: child) == [.removeFromParent])

        // UIKit later sends another didMove(toParent: nil) when the view disappears.
        await settle()
        child.didMove(toParent: nil)
        #expect(recorder.triggers(for: child) == [.removeFromParent])
        #expect(recorder.triggers(for: host).isEmpty)
        withExtendedLifetime(window) {}
    }

    // MARK: Modal
    // Package tests have no app host, so a real presentation never finishes: fake `isBeingDismissed`.

    @Test("viewDidDisappear while being dismissed marks once; a plain disappear does not")
    func dismiss() {
        let presented = DismissableVC()
        presented.viewDidDisappear(false)
        #expect(recorder.triggers(for: presented).isEmpty)

        presented.fakeBeingDismissed = true
        presented.viewDidDisappear(true)
        #expect(recorder.triggers(for: presented) == [.dismiss])
    }

    @Test("Dismissing a presented container: only the container is marked, not each child")
    func dismissPresentedContainer() {
        let nav = DismissableNav(rootViewController: HookVC())
        let inner = DismissableVC()
        nav.pushViewController(inner, animated: false)
        nav.fakeBeingDismissed = true
        inner.fakeBeingDismissed = true                    // UIKit may report it for children too

        inner.viewDidDisappear(true)
        nav.viewDidDisappear(true)
        #expect(recorder.triggers(for: inner).isEmpty)
        #expect(recorder.triggers(for: nav) == [.dismiss])
    }

    @Test("A presented UINavigationController is walked but not marked")
    func presentedNavigationSubtree() {
        let inner = HookVC(), pushed = HookVC()
        let nav = UINavigationController(rootViewController: inner)
        nav.pushViewController(pushed, animated: false)
        let collected = SubtreeCollector.collect(from: nav, filter: testFilter)
        #expect(!collected.contains { $0.object === nav })
        #expect(collected.contains { $0.object === inner && $0.path == "UINavigationController.children[0]" })
        #expect(collected.contains { $0.object === pushed && $0.path == "UINavigationController.children[1]" })
    }

    @Test("UISearchController is reused after dismissal: never marked")
    func searchControllerSkipped() {
        let search = DismissableSearch(searchResultsController: HookVC())
        search.fakeBeingDismissed = true
        search.viewDidDisappear(true)
        #expect(recorder.triggers(for: search).isEmpty)
    }

    // MARK: Window

    @Test("Replacing the window root marks the old root once")
    func replaceRoot() {
        let old = HookVC(), new = HookVC()
        let window = makeWindow(root: old)
        #expect(recorder.triggers(for: old).isEmpty)

        window.rootViewController = new
        #expect(recorder.triggers(for: old) == [.replaceRoot])
        window.rootViewController = new
        #expect(recorder.triggers(for: new).isEmpty)
        withExtendedLifetime(window) {}
    }

    // MARK: System view controllers

    @Test("System view controllers are never marked")
    func systemControllersNotMarked() {
        let registry = LeakRegistry(scheduler: MainQueueScheduler(), attachment: NeverAttached()) { _ in }
        TLeakDetector.leaveHandler = { vc, trigger in
            TLeakDetector.expectDeallocation(of: vc, trigger: trigger, in: registry, filter: testFilter)
        }
        let alert = UIAlertController(title: "t", message: nil, preferredStyle: .alert)
        alert.loadViewIfNeeded()
        TLeakDetector.leaveHandler(alert, .dismiss)
        if let inputController = NSClassFromString("UIInputViewController") as? UIViewController.Type {
            TLeakDetector.leaveHandler(inputController.init(), .removeFromParent)
        }
        TLeakDetector.leaveHandler(UINavigationController(), .pop)
        TLeakDetector.leaveHandler(UITabBarController(), .removeFromParent)
        #expect(registry.pendingCount == 0)

        TLeakDetector.leaveHandler(UINavigationController(rootViewController: HookVC()), .pop)
        #expect(registry.pendingCount == 1)
    }
}

/// Same container path as a back swipe.
@MainActor
private final class InteractivePop: NSObject, UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning {
    let interaction = UIPercentDrivenInteractiveTransition()
    private(set) var animationStarted = false

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController, to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        operation == .pop ? self : nil
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.25 }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        animationStarted = true
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to) else {
            context.completeTransition(false)
            return
        }
        context.containerView.insertSubview(to, belowSubview: from)
        let width = context.containerView.bounds.width
        UIView.animate(withDuration: 0.25, animations: {
            from.transform = CGAffineTransform(translationX: width, y: 0)
        }, completion: { _ in
            from.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        })
    }
}

#endif
