//
//  LeaveHooks.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import ObjectiveC
import LeakCore

/// Marks in `didMove`, not `willMove`: a cancelled interactive pop calls only `willMove(toParent: nil)`.
/// Also counts view controllers for instance budgets at `viewDidLoad`.
@MainActor
enum LeaveHooks {
    /// Not `LeakCore.isInstalled`: that one can be reset, and swizzling twice undoes it.
    private(set) static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        swizzle(UIViewController.self,
                #selector(UIViewController.willMove(toParent:)),
                #selector(UIViewController.tld_willMove(toParent:)))
        swizzle(UIViewController.self,
                #selector(UIViewController.didMove(toParent:)),
                #selector(UIViewController.tld_didMove(toParent:)))
        swizzle(UIViewController.self,
                #selector(UIViewController.viewDidDisappear(_:)),
                #selector(UIViewController.tld_viewDidDisappear(_:)))
        swizzle(UIViewController.self,
                #selector(UIViewController.viewDidLoad),
                #selector(UIViewController.tld_viewDidLoad))
        swizzle(UIWindow.self,
                #selector(setter: UIWindow.rootViewController),
                #selector(UIWindow.tld_setRootViewController(_:)))
    }

    private static func swizzle(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let replacementMethod = class_getInstanceMethod(cls, replacement) else {
            assertionFailure("TLeakDetector: cannot swizzle \(cls).\(original)")
            return
        }
        if class_addMethod(cls, original, method_getImplementation(replacementMethod),
                           method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(cls, replacement, method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    private static var pendingTriggerKey: UInt8 = 0

    private static func pendingTrigger(of vc: UIViewController) -> LeakTrigger? {
        (objc_getAssociatedObject(vc, &pendingTriggerKey) as? String).flatMap(LeakTrigger.init(rawValue:))
    }

    private static func setPendingTrigger(_ trigger: LeakTrigger?, of vc: UIViewController) {
        objc_setAssociatedObject(vc, &pendingTriggerKey, trigger?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    fileprivate static func willMove(_ vc: UIViewController, toParent parent: UIViewController?) {
        let trigger: LeakTrigger? = parent == nil
            ? (vc.parent is UINavigationController ? .pop : .removeFromParent)
            : nil
        setPendingTrigger(trigger, of: vc)
    }

    fileprivate static func didMove(_ vc: UIViewController, toParent parent: UIViewController?) {
        let trigger = pendingTrigger(of: vc)
        setPendingTrigger(nil, of: vc)
        // UIKit sends a second didMove(toParent: nil), without willMove, when a removed child's view disappears.
        guard parent == nil, let trigger else { return }
        TLeakDetector.leaveHandler(vc, trigger)
    }

    fileprivate static func didDisappear(_ vc: UIViewController) {
        guard vc.isBeingDismissed else { return }
        var ancestor = vc.parent
        while let current = ancestor {
            if current.isBeingDismissed { return }
            ancestor = current.parent
        }
        if vc is UISearchController { return }   // reused after dismissal
        TLeakDetector.leaveHandler(vc, .dismiss)
    }

    fileprivate static func replacedRoot(_ old: UIViewController?, with new: UIViewController?) {
        guard let old, old !== new else { return }
        TLeakDetector.leaveHandler(old, .replaceRoot)
    }
}

extension UIViewController {
    @objc dynamic func tld_viewDidLoad() {
        tld_viewDidLoad()
        TLeakDetector.loadHandler(self)
    }

    @objc dynamic func tld_willMove(toParent parent: UIViewController?) {
        tld_willMove(toParent: parent)
        LeaveHooks.willMove(self, toParent: parent)
    }

    @objc dynamic func tld_didMove(toParent parent: UIViewController?) {
        tld_didMove(toParent: parent)
        LeaveHooks.didMove(self, toParent: parent)
    }

    @objc dynamic func tld_viewDidDisappear(_ animated: Bool) {
        tld_viewDidDisappear(animated)
        LeaveHooks.didDisappear(self)
    }
}

extension UIWindow {
    @objc dynamic func tld_setRootViewController(_ new: UIViewController?) {
        let old = rootViewController
        tld_setRootViewController(new)
        LeaveHooks.replacedRoot(old, with: new)
    }
}

#endif
