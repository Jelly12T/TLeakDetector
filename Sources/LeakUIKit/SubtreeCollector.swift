//
//  SubtreeCollector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import LeakCore

struct SubtreeFilter: Sendable {
    /// VCs rejected here (system containers, alerts…) are not marked, but their children are still walked.
    var viewController: @Sendable (AnyClass) -> Bool
    var property: @Sendable (AnyClass) -> Bool

    static let app = SubtreeFilter(viewController: isAppType, property: isAppType)
}

/// Everything that must die together with a closing view controller:
/// the VC, its children, what it presented, its whole view hierarchy, and the
/// app-module objects held in its stored properties.
@MainActor
enum SubtreeCollector {
    struct Item {
        let object: AnyObject
        let path: String
    }

    static func collect(from root: UIViewController, filter: SubtreeFilter) -> [Item] {
        var walker = Walker(filter: filter)
        walker.visit(root, path: String(describing: type(of: root)))
        return walker.items
    }

    @MainActor
    private struct Walker {
        let filter: SubtreeFilter
        var items: [Item] = []
        var seen: Set<ObjectIdentifier> = []

        mutating func add(_ object: AnyObject, path: String) -> Bool {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return false }
            items.append(Item(object: object, path: path))
            return true
        }

        mutating func visit(_ vc: UIViewController, path: String) {
            let isApp = filter.viewController(type(of: vc))
            if isApp {
                guard add(vc, path: path) else { return }
            } else {
                guard seen.insert(ObjectIdentifier(vc)).inserted else { return }
            }

            // Children first, so their views get the child's path.
            for (index, child) in vc.children.enumerated() {
                visit(child, path: "\(path).children[\(index)]")
            }
            // Only what this VC itself presented: `presentedViewController` can also
            // return a VC presented by an ancestor.
            if let presented = vc.presentedViewController, presented.presentingViewController === vc {
                visit(presented, path: "\(path).presented")
            }
            guard isApp else { return }

            // Never force-load a view that was never shown.
            if let view = vc.viewIfLoaded {
                visit(view, path: "\(path).view")
            }
            for property in PropertyScanner.classProperties(of: vc, include: filter.property) {
                _ = add(property.object, path: "\(path).\(property.label)")
            }
        }

        mutating func visit(_ view: UIView, path: String) {
            guard add(view, path: path) else { return }
            for (index, subview) in view.subviews.enumerated() {
                visit(subview, path: "\(path).subviews[\(index)]")
            }
        }
    }
}

/// Types in the app's own dynamic frameworks do not count.
func isAppType(_ cls: AnyClass) -> Bool {
    Bundle(for: cls) == Bundle.main
}

#endif
