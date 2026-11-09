//
//  TLeakDetector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import Foundation
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
        LeaveHooks.install()
    }

    public static var isInstalled: Bool { LeakCore.isInstalled }

    static let registry = LeakRegistry(
        scheduler: MainQueueScheduler(),
        attachment: UIKitAttachmentChecker(),
        onLeak: { print("[TLeakDetector] LEAK? \($0)") })

    /// `TLEAK_VERBOSE=1` logs every mark.
    static let isVerbose = ProcessInfo.processInfo.environment["TLEAK_VERBOSE"] == "1"

    static var leaveHandler: @MainActor (UIViewController, LeakTrigger) -> Void = { vc, trigger in
        expectDeallocation(of: vc, trigger: trigger)
    }

    static func expectDeallocation(of viewController: UIViewController, trigger: LeakTrigger) {
        expectDeallocation(of: viewController, trigger: trigger, in: registry, filter: .app)
    }

    @discardableResult
    static func expectDeallocation(
        of viewController: UIViewController,
        trigger: LeakTrigger,
        in registry: LeakRegistry,
        filter: SubtreeFilter
    ) -> Int {
        let items = SubtreeCollector.collect(from: viewController, filter: filter)
        guard !items.isEmpty else { return 0 }
        let rootName = String(describing: type(of: viewController))
        for item in items {
            registry.expectDeallocation(
                of: item.object,
                context: LeakContext(trigger: trigger, rootTypeName: rootName, path: item.path))
        }
        if isVerbose {
            print("[TLeakDetector] mark \(trigger.rawValue) \(rootName) (\(items.count) objects)")
        }
        return items.count
    }
}

#endif
