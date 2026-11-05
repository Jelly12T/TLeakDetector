//
//  TLeakDetector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import LeakCore

/// Public entry point. Call once at launch, inside `#if DEBUG`:
///
///     #if DEBUG
///     TLeakDetector.install()
///     #endif
@MainActor
public enum TLeakDetector {
    public static func install() {
        guard LeakCore.markInstalled() else { return }
        // Next sprint: UIViewController hooks call `expectDeallocation(of:trigger:)`.
    }

    public static var isInstalled: Bool { LeakCore.isInstalled }

    static let registry = LeakRegistry(
        scheduler: MainQueueScheduler(),
        attachment: UIKitAttachmentChecker(),
        onLeak: { print("[TLeakDetector] LEAK? \($0)") })

    /// Marks `viewController` and its whole subtree as "must die soon".
    static func expectDeallocation(of viewController: UIViewController, trigger: LeakTrigger) {
        expectDeallocation(of: viewController, trigger: trigger, in: registry, includeProperty: isAppType)
    }

    static func expectDeallocation(
        of viewController: UIViewController,
        trigger: LeakTrigger,
        in registry: LeakRegistry,
        includeProperty: (AnyClass) -> Bool
    ) {
        let rootName = String(describing: type(of: viewController))
        for item in SubtreeCollector.collect(from: viewController, includeProperty: includeProperty) {
            registry.expectDeallocation(
                of: item.object,
                context: LeakContext(trigger: trigger, rootTypeName: rootName, path: item.path))
        }
    }
}

#endif
