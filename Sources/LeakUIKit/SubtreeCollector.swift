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
    /// Allowed to outlive the screen: not marked, and nothing below them is walked.
    var exempt: @Sendable (AnyClass) -> Bool = { _ in false }
    /// The root is at depth 0.
    var maxDepth = Int.max

    static func app(_ configuration: LeakConfiguration) -> SubtreeFilter {
        SubtreeFilter(viewController: isAppType, property: isAppType,
                      exempt: configuration.isExempt,
                      maxDepth: configuration.maxSubtreeDepth ?? .max)
    }
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
        walker.visit(root, path: String(describing: type(of: root)), depth: 0)
        return walker.items
    }

    @MainActor
    private struct Walker {
        let filter: SubtreeFilter
        var items: [Item] = []
        var seen: Set<ObjectIdentifier> = []

        /// First visit of an object that is neither too deep nor exempt.
        mutating func enter(_ object: AnyObject, depth: Int) -> Bool {
            guard depth <= filter.maxDepth, seen.insert(ObjectIdentifier(object)).inserted else { return false }
            guard filter.exempt(type(of: object)) else { return true }
            // An exempt VC keeps its view alive too, even when that view sits in the parent's hierarchy.
            if let vc = object as? UIViewController, let view = vc.viewIfLoaded {
                seen.insert(ObjectIdentifier(view))
            }
            return false
        }

        mutating func visit(_ vc: UIViewController, path: String, depth: Int) {
            guard enter(vc, depth: depth) else { return }
            let isApp = filter.viewController(type(of: vc))
            if isApp {
                items.append(Item(object: vc, path: path))
            }

            // Children first, so their views get the child's path.
            for (index, child) in vc.children.enumerated() {
                visit(child, path: "\(path).children[\(index)]", depth: depth + 1)
            }
            // Only what this VC itself presented: `presentedViewController` can also
            // return a VC presented by an ancestor.
            if let presented = vc.presentedViewController, presented.presentingViewController === vc {
                visit(presented, path: "\(path).presented", depth: depth + 1)
            }
            guard isApp else { return }

            // Never force-load a view that was never shown.
            if let view = vc.viewIfLoaded {
                visit(view, path: "\(path).view", depth: depth + 1)
            }
            for property in PropertyScanner.classProperties(of: vc, include: filter.property) {
                if enter(property.object, depth: depth + 1) {
                    items.append(Item(object: property.object, path: "\(path).\(property.label)"))
                }
            }
        }

        mutating func visit(_ view: UIView, path: String, depth: Int) {
            guard enter(view, depth: depth) else { return }
            items.append(Item(object: view, path: path))
            for (index, subview) in view.subviews.enumerated() {
                visit(subview, path: "\(path).subviews[\(index)]", depth: depth + 1)
            }
        }
    }
}

/// Types in the app's own dynamic frameworks do not count.
func isAppType(_ cls: AnyClass) -> Bool {
    Bundle(for: cls) == Bundle.main
}

#endif
