//
//  UIKitAttachmentChecker.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import LeakCore

/// "Back in the live hierarchy?"
/// - View: it is in a window.
/// - View controller: walking up `parent` / `presentingViewController` reaches a VC whose
///   view is in a window. This covers non-top VCs in a navigation stack and hidden tabs, and
///   does *not* count a VC whose parent is itself detached (e.g. a child of a leaked VC).
/// - Anything else: never attached.
@MainActor
struct UIKitAttachmentChecker: LeakAttachmentChecking {
    func isAttached(_ object: AnyObject) -> Bool {
        switch object {
        case let vc as UIViewController: return Self.isAttached(vc)
        case let view as UIView: return view.window != nil
        default: return false
        }
    }

    static func isAttached(_ vc: UIViewController) -> Bool {
        var current: UIViewController? = vc
        var depth = 0
        while let candidate = current, depth < 64 {
            if candidate.viewIfLoaded?.window != nil { return true }
            current = candidate.parent ?? candidate.presentingViewController
            depth += 1
        }
        return false
    }
}

#endif
