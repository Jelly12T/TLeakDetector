//
//  SubtreeCollector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import LeakCore

/// Everything that must die together with a closing view controller:
/// the VC, its children, what it presented, its whole view hierarchy, and the
/// app-module objects held in its stored properties.
@MainActor
enum SubtreeCollector {
    struct Item {
        let object: AnyObject
        let path: String
    }

    /// - Parameter includeProperty: which property types to follow (default: types in the app bundle).
    static func collect(from root: UIViewController, includeProperty: (AnyClass) -> Bool) -> [Item] {
        withoutActuallyEscaping(includeProperty) { include in
            var walker = Walker(includeProperty: include)
            walker.visit(root, path: String(describing: type(of: root)))
            return walker.items
        }
    }

    private struct Walker {
        let includeProperty: (AnyClass) -> Bool
        var items: [Item] = []
        var seen: Set<ObjectIdentifier> = []

        mutating func add(_ object: AnyObject, path: String) -> Bool {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return false }
            items.append(Item(object: object, path: path))
            return true
        }

        mutating func visit(_ vc: UIViewController, path: String) {
            guard add(vc, path: path) else { return }

            // Children first, so their views get the child's path.
            for (index, child) in vc.children.enumerated() {
                visit(child, path: "\(path).children[\(index)]")
            }
            // Only what this VC itself presented: `presentedViewController` can also
            // return a VC presented by an ancestor.
            if let presented = vc.presentedViewController, presented.presentingViewController === vc {
                visit(presented, path: "\(path).presented")
            }
            // Never force-load a view that was never shown.
            if let view = vc.viewIfLoaded {
                visit(view, path: "\(path).view")
            }
            for property in PropertyScanner.classProperties(of: vc, include: includeProperty) {
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

/// Default property filter: the type is compiled into the app itself.
func isAppType(_ cls: AnyClass) -> Bool {
    Bundle(for: cls) == Bundle.main
}

#endif
