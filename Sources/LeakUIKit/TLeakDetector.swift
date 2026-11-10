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
import LeakConcurrency
import LeakGraph
import LeakHeap
import LeakPatterns
import os

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
    private(set) static var checks = LeakChecks(isEnabled: false, tracksTasks: false)
    private(set) static var reporter = LeakReporter(mode: modeOverride)
    private(set) static var registry = makeRegistry(LeakConfiguration())
    private(set) static var budgets = LeakBudgetCounter([], onOverBudget: { reporter.report($0) })

    static func apply(_ configuration: LeakConfiguration) {
        let loaded = configuration.suppressionFile.map { LeakSuppressionFile.load($0) } ?? .init()
        for problem in loaded.problems {
            LeakLog.config.error("[TLeakDetector] \(problem, privacy: .public)")
        }
        filter = .app(configuration)
        checks = configuration.checks
        let graph = configuration.graph
        reporter = LeakReporter(mode: modeOverride ?? configuration.mode, suppressions: loaded.suppressions,
                                exportDirectory: graph.isEnabled ? graph.exportDirectory : nil,
                                ignoredPatterns: checks.ignoredPatterns, verbose: isVerbose)
        registry = makeRegistry(configuration)
        // Also as early as possible: only what is created from now on is seen.
        if checks.isEnabled { FrameworkHolds.shared.install() }
        if checks.tracksTasks { TaskRegistry.install(includeImage: AssociatedObjects.isAppImage) }
        // As early as possible: associations set before this are not seen.
        if graph.isEnabled {
            AssociatedObjects.install()
            DispatchQueue.global(qos: .utility).async {
                LiveHeap.warmUp(classes: [UIViewController.self, UINavigationController.self, UITabBarController.self,
                                          UIView.self, UIWindow.self, UILabel.self, UIButton.self, UIImageView.self,
                                          UIStackView.self, UIScrollView.self, UITableView.self, UICollectionView.self,
                                          UIPresentationController.self, UITraitCollection.self])
            }
        }
        budgets = LeakBudgetCounter(configuration.instanceBudgets, onOverBudget: { reporter.report($0) })
    }

    /// Counts `object` against its `LeakInstanceBudget`. Call at the end of `init`, inside `#if DEBUG`.
    /// View controllers are counted at `viewDidLoad` without it.
    public nonisolated static func track(_ object: AnyObject) {
        let pending = PendingTrack(object)
        if Thread.isMainThread {
            MainActor.assumeIsolated { pending.track() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { pending.track() } }
        }
    }

    private static func makeRegistry(_ configuration: LeakConfiguration) -> LeakRegistry {
        LeakRegistry(
            scheduler: MainQueueScheduler(),
            attachment: UIKitAttachmentChecker(),
            configuration: .init(t1: configuration.t1, t2: configuration.t2),
            cycleSearch: configuration.graph.isEnabled ? cycleSearch(configuration.graph) : nil,
            onLeak: { reporter.report($0) })
    }

    static func cycleSearch(_ options: LeakGraphOptions, scheduler: LeakScheduler = MainQueueScheduler()) -> LeakCycleSearch {
        let limits = RetainCycleSearch.Limits(maxDepth: options.maxDepth, maxNodes: options.maxNodes,
                                              maxDuration: options.maxDuration)
        return { object, completion in
            if let task = object as? TaskProbe {
                completion(LeakAnalysis(cause: .running(task.holder)))
                return
            }
            SlicedAnalysis(object: object, limits: limits, options: options, scheduler: scheduler, completion: completion).start()
        }
    }

    static var leaveHandler: @MainActor (UIViewController, LeakTrigger) -> Void = { vc, trigger in
        expectDeallocation(of: vc, trigger: trigger)
    }

    static var loadHandler: @MainActor (UIViewController) -> Void = { budgets.track($0) }

    static func expectDeallocation(of viewController: UIViewController, trigger: LeakTrigger) {
        expectDeallocation(of: viewController, trigger: trigger, in: registry, filter: filter)
    }

    @discardableResult
    static func expectDeallocation(
        of viewController: UIViewController,
        trigger: LeakTrigger,
        in registry: LeakRegistry,
        filter: SubtreeFilter,
        checks: LeakChecks = TLeakDetector.checks
    ) -> Int {
        let items = SubtreeCollector.collect(from: viewController, filter: filter)
        guard !items.isEmpty else { return 0 }
        let rootName = String(describing: type(of: viewController))
        let context = LeakContext(trigger: trigger, rootTypeName: rootName)
        var members = items.map { (object: $0.object, path: $0.path) }
        if checks.isEnabled {
            for warning in PatternChecker.warnings(members: members, context: context) { reporter.warn(warning) }
        }
        if checks.tracksTasks {
            // Tasks working for the screen must end with it: each is watched like one more member.
            let owners = members.map(\.object).filter { SymbolNames.isAppClass(type(of: $0)) }
            for task in TaskRegistry.tasks(pointingTo: owners) {
                members.append((TaskProbe(task), "Task (\(task.operation))"))
            }
        }
        registry.expectDeallocation(of: members, root: viewController, context: context)
        if isVerbose {
            LeakLog.marks.notice("mark \(trigger.rawValue, privacy: .public) \(rootName, privacy: .public) (\(members.count) objects)")
        }
        return members.count
    }
}

/// What UIKit retains where no ivar shows it: a view holds its subviews through its layer tree.
enum UIKitReferences {
    @MainActor
    static func of(_ object: AnyObject) -> [(path: RetainPath, target: AnyObject)] {
        // A class check, not a cast: casting messages the object, and a proxy would forward it.
        guard inheritsFromUIView(type(of: object)) else { return [] }
        return unsafeDowncast(object, to: UIView.self).subviews.enumerated().map {
            (RetainPath([.field("subviews"), .element($0.offset)]), $0.element)
        }
    }

    private static func inheritsFromUIView(_ cls: AnyClass) -> Bool {
        var current: AnyClass? = cls
        while let candidate = current {
            if candidate === UIView.self { return true }
            current = class_getSuperclass(candidate)
        }
        return false
    }
}

/// Why an object is still alive, a slice per main run loop turn so frames keep being drawn in between:
/// first a cycle through it; unless that cycle is certain, then what holds it among the roots the tool
/// knows (running tasks, timers, observers, display links, sessions).
@MainActor
private final class SlicedAnalysis: @unchecked Sendable {
    private let object: AnyObject
    private let limits: RetainCycleSearch.Limits
    private let options: LeakGraphOptions
    private let scheduler: LeakScheduler
    private let completion: @MainActor (LeakAnalysis) -> Void
    private let typeName: String
    private var interval: OSSignpostIntervalState?
    private var slices = 0
    private var longestSlice: Double = 0
    private var spent: Double = 0

    init(object: AnyObject, limits: RetainCycleSearch.Limits, options: LeakGraphOptions, scheduler: LeakScheduler,
         completion: @escaping @MainActor (LeakAnalysis) -> Void) {
        self.object = object
        self.limits = limits
        self.options = options
        self.scheduler = scheduler
        self.completion = completion
        typeName = String(describing: type(of: object))
    }

    static func heap() -> LiveHeap {
        LiveHeap(extraReferences: { UIKitReferences.of($0) + FrameworkHolds.shared.references(of: $0) })
    }

    func start() {
        interval = LeakLog.graph.beginInterval("retain graph")
        let searcher = RetainCycleSearcher(source: Self.heap(), start: .object(object), limits: limits,
                                           prunedModules: options.prunedModules)
        run(searcher) { [self] cycle in
            guard !LeakCause(cycle).isCertainCycle else { return finish(LeakAnalysis(cycle), searched: [cycle]) }
            searchHolders(otherwise: cycle)
        }
    }

    private func searchHolders(otherwise cycle: RetainCycleSearch) {
        var holders: [RetainGraph.Node.ID: LeakHolder] = [:]
        var roots: [LiveHeap.Object] = []
        let heap = Self.heap()
        let tasks = TaskRegistry.isInstalled ? TaskRegistry.liveTasks() : []
        for task in tasks {
            holders[heap.node(for: task.root).id] = task.holder
            roots.append(task.root)
        }
        for root in FrameworkHolds.shared.roots() {
            holders[heap.node(for: .object(root.object)).id] = root.holder
            roots.append(.object(root.object))
        }
        guard !roots.isEmpty else { return finish(LeakAnalysis(cycle), searched: [cycle]) }
        let goal = UInt(bitPattern: ObjectIdentifier(object))
        let searcher = RetainCycleSearcher(source: heap, starts: roots, goals: [goal], limits: limits, prunedModules: options.prunedModules)
        run(searcher) { [self] held in
            withExtendedLifetime(tasks) {}
            guard case .found(let chain) = held.outcome, let holder = holders[chain.nodes.first?.id ?? chain.end.id] else {
                return finish(LeakAnalysis(cycle), searched: [cycle, held])
            }
            finish(LeakAnalysis(cause: .heldBy(holder, chain), explored: held.explored, highlighted: chain), searched: [cycle, held])
        }
    }

    private func run<Source>(_ searcher: RetainCycleSearcher<Source>, then next: @escaping @MainActor (RetainCycleSearch) -> Void) {
        let began = DispatchTime.now().uptimeNanoseconds
        let finished = searcher.advance(for: options.sliceDuration)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9
        slices += 1
        longestSlice = max(longestSlice, elapsed)
        spent += elapsed
        guard let search = finished else {
            scheduler.schedule(after: 0) { [self] in run(searcher, then: next) }
            return
        }
        next(search)
    }

    private func finish(_ analysis: LeakAnalysis, searched: [RetainCycleSearch]) {
        if let interval { LeakLog.graph.endInterval("retain graph", interval) }
        if TLeakDetector.isVerbose {
            let objects = searched.map(\.explored.nodes.count).reduce(0, +)
            let total = String(format: "%.2f", spent * 1_000), longest = String(format: "%.2f", longestSlice * 1_000)
            LeakLog.marks.notice("graph \(self.typeName, privacy: .public): \(objects) objects in \(total, privacy: .public) ms over \(self.slices) slices, longest \(longest, privacy: .public) ms, \(String(describing: analysis.cause), privacy: .public)")
        }
        completion(analysis)
    }
}

/// Hands an object from any thread to the main actor without keeping it alive. Only read on main.
private final class PendingTrack: @unchecked Sendable {
    private weak var object: AnyObject?

    init(_ object: AnyObject) { self.object = object }

    @MainActor func track() {
        if let object { TLeakDetector.budgets.track(object) }
    }
}

#endif
