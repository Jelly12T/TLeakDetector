//
//  LeakWarning.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

/// Classic leak patterns spotted when a screen closes, before any leak is confirmed.
/// Raw values are written in configuration: never rename them.
public enum LeakPattern: String, Sendable, CaseIterable {
    /// A stored `delegate` or `dataSource` that holds its object strongly.
    case strongDelegate
    /// A scheduled timer, still valid, whose target or block holds the screen.
    case timerTarget
    /// A display link, never invalidated, whose target is part of the screen.
    case displayLinkTarget
    /// A URLSession, not invalidated, whose delegate is part of the screen.
    case urlSessionDelegate
    /// A WKUserContentController still holding part of the screen as a script message handler.
    case scriptMessageHandler
    /// A NotificationCenter observer, still registered, whose block holds the screen.
    case observerBlock
}

/// Logged once per pattern and place, never pauses or crashes: it may not leak yet.
package struct LeakWarning: Sendable, CustomStringConvertible {
    package let pattern: LeakPattern
    /// The object holding too strongly: `Worker` for `Worker.delegate`.
    package let typeName: String
    /// `Worker.delegate holds ProfileVC strongly`.
    package let detail: String
    package let fix: String
    package let context: LeakContext

    package init(pattern: LeakPattern, typeName: String, detail: String, fix: String, context: LeakContext) {
        self.pattern = pattern
        self.typeName = typeName
        self.detail = detail
        self.fix = fix
        self.context = context
    }

    /// The same warning about the same place is logged once per run.
    package var key: String { "\(pattern.rawValue) \(detail)" }

    package var description: String {
        [
            "[TLeakDetector] WARNING \(pattern.rawValue): \(detail)",
            "  seen when \(context.rootTypeName) closed (\(context.trigger.rawValue)): it leaks unless something releases it later",
            "  fix: \(fix)",
        ].joined(separator: "\n")
    }
}

/// What to change, from the shape of the cause. Wording addresses the developer who reads the report.
package enum LeakFixes {
    package static func suggestions(for cause: LeakCause) -> [String] {
        var fixes: [String] = []
        func add(_ fix: String) { if !fixes.contains(fix) { fixes.append(fix) } }
        switch cause {
        case .cycle(let chain):
            for fix in suggestions(for: chain) { add(fix) }
            if fixes.isEmpty { add("make one reference of the cycle weak, or clear it when the screen closes") }
        case .heldBy(let holder, let chain):
            add(fix(for: holder.kind))
            for fix in suggestions(for: chain) { add(fix) }
        case .running(let holder):
            add(fix(for: holder.kind))
        case .noCycle:
            add("look for a static, a singleton or a cache keeping it (Xcode Memory Graph: select it to see who references it)")
        case .unknown:
            break
        }
        return fixes
    }

    package static func fix(for holder: LeakHolder.Kind) -> String {
        switch holder {
        case .task:
            "cancel the task when the screen closes: keep it (`task = Task { … }`), call `task?.cancel()` in viewDidDisappear, "
                + "and capture self weakly inside; a `for await` over an AsyncStream only ends when its continuation calls `finish()`"
        case .timer:
            "invalidate the timer when the screen closes (viewWillDisappear): a scheduled timer keeps its target or block, so deinit never runs"
        case .displayLink:
            "invalidate the display link when the screen closes: it retains its target; or give it a weak proxy as target"
        case .notificationObserver:
            "remove the observer when the screen closes (`NotificationCenter.default.removeObserver(token)`), and capture self weakly in its block"
        case .urlSession:
            "invalidate the session when done (`finishTasksAndInvalidate()`): a URLSession retains its delegate until then"
        }
    }

    package static let scriptMessageHandlerFix =
        "remove the handler when the screen closes (`removeScriptMessageHandler(forName:)`), or register a weak proxy: "
        + "WKUserContentController retains its script message handlers"

    package static func weakDelegateFix(_ owner: String, _ field: String) -> String {
        "declare `\(owner).\(field)` as `weak var` (and its protocol as `AnyObject`)"
    }

    private static func suggestions(for chain: RetainChain) -> [String] {
        var fixes: [String] = []
        for index in chain.nodes.indices {
            let from = chain.nodes[index], to = chain.target(of: index)
            for step in chain.paths[index].steps {
                switch step {
                case .closure(let function) where isAppClosure(function):
                    fixes.append(weakSelfFix(function))
                case .associatedObject(let key):
                    fixes.append("associate `\(key)` with `.OBJC_ASSOCIATION_ASSIGN`, or store a weak box under it")
                default:
                    break
                }
            }
            if case .closure(let function) = to.kind, isAppClosure(function) {
                fixes.append(weakSelfFix(function))
            }
            if let field = chain.paths[index].steps.last.flatMap(fieldName), isDelegateName(field) {
                fixes.append(weakDelegateFix(from.name, field))
            }
            for node in [from, to] {
                if let fix = fix(forType: node.name) { fixes.append(fix) }
            }
        }
        return fixes
    }

    private static func fix(forType name: String) -> String? {
        if name.hasSuffix("Timer") { return fix(for: .timer) }
        if name == "CADisplayLink" { return fix(for: .displayLink) }
        if name.contains("URLSession") { return fix(for: .urlSession) }
        if name == "__NSObserver" { return fix(for: .notificationObserver) }
        if name == "WKUserContentController" { return scriptMessageHandlerFix }
        if name.hasPrefix("Subscribers.Sink") {
            return "capture self weakly in the `sink` closure, or use `assign(to: &$property)` instead of `assign(to:on: self)`"
        }
        if name.hasPrefix("Subscribers.Assign") {
            return "`assign(to:on: self)` retains self: use `assign(to: &$property)` or a `sink` with `[weak self]`"
        }
        return nil
    }

    private static func weakSelfFix(_ function: String) -> String {
        "capture self weakly in \(function): `{ [weak self] in … }`"
    }

    /// Closures named after a system image carry no useful place to change.
    private static func isAppClosure(_ function: String) -> Bool {
        function != "closure" && !function.hasPrefix("closure in ")
    }

    private static func fieldName(_ step: RetainPath.Step) -> String? {
        if case .field(let name) = step { return name.hasPrefix("_") ? String(name.dropFirst()) : name }
        return nil
    }

    package static func isDelegateName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasSuffix("delegate") || lowered.hasSuffix("datasource")
    }
}

#endif
