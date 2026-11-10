//
//  TLeakDetector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import Foundation
import UIKit
@_exported import LeakCore

/// Public entry point. Call once at launch, inside `#if DEBUG`:
///
///     #if DEBUG
///     TLeakDetector.install()
///     #endif
@MainActor
public enum TLeakDetector {
    public static func install(_ configuration: LeakConfiguration = LeakConfiguration()) {
        guard LeakCore.markInstalled() else { return }
        apply(configuration)
        LeaveHooks.install()
    }

    public static var isInstalled: Bool { LeakCore.isInstalled }

    private static let environment = ProcessInfo.processInfo.environment
    /// `TLEAK_VERBOSE=1` logs every mark.
    static let isVerbose = environment["TLEAK_VERBOSE"] == "1"
    /// `TLEAK_MODE=crash|debugger|log` overrides `LeakConfiguration.mode`.
    private static let modeOverride = environment["TLEAK_MODE"].flatMap(LeakReportMode.init(rawValue:))

    private(set) static var filter = SubtreeFilter.app(LeakConfiguration())
    private(set) static var reporter = LeakReporter(mode: modeOverride)
    private(set) static var registry = makeRegistry(LeakConfiguration())

    static func apply(_ configuration: LeakConfiguration) {
        let loaded = configuration.suppressionFile.map { LeakSuppressionFile.load($0) } ?? .init()
        for problem in loaded.problems {
            LeakLog.config.error("[TLeakDetector] \(problem, privacy: .public)")
        }
        filter = .app(configuration)
        reporter = LeakReporter(mode: modeOverride ?? configuration.mode, suppressions: loaded.suppressions)
        registry = makeRegistry(configuration)
    }

    private static func makeRegistry(_ configuration: LeakConfiguration) -> LeakRegistry {
        LeakRegistry(
            scheduler: MainQueueScheduler(),
            attachment: UIKitAttachmentChecker(),
            configuration: .init(t1: configuration.t1, t2: configuration.t2),
            onLeak: { reporter.report($0) })
    }

    static var leaveHandler: @MainActor (UIViewController, LeakTrigger) -> Void = { vc, trigger in
        expectDeallocation(of: vc, trigger: trigger)
    }

    static func expectDeallocation(of viewController: UIViewController, trigger: LeakTrigger) {
        expectDeallocation(of: viewController, trigger: trigger, in: registry, filter: filter)
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
