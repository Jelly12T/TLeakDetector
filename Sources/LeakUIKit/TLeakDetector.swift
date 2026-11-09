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

    /// `TLEAK_MODE=crash|debugger|log` overrides the default (debugger if attached, else crash).
    static let reporter = LeakReporter(
        mode: ProcessInfo.processInfo.environment["TLEAK_MODE"].flatMap(LeakReportMode.init(rawValue:)))

    static let registry = LeakRegistry(
        scheduler: MainQueueScheduler(),
        attachment: UIKitAttachmentChecker(),
        onLeak: { reporter.report($0) })

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
        registry.expectDeallocation(
            of: items.map { (object: $0.object, path: $0.path) },
            root: viewController,
            context: LeakContext(trigger: trigger, rootTypeName: rootName))
        if isVerbose {
            LeakLog.marks.debug("mark \(trigger.rawValue, privacy: .public) \(rootName, privacy: .public) (\(items.count) objects)")
        }
        return items.count
    }
}

#endif
