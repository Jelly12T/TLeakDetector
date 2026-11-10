//
//  LeakReport.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

/// What was observed, not why. Raw values are written in suppression files: never rename them (ADR 003).
package enum LeakKind: String, Sendable, CaseIterable {
    /// The closed screen itself is still alive.
    case screen
    /// The screen is gone but this object is not: something outside the screen holds it.
    case outlived
    /// More instances of a type alive at once than its declared budget.
    case budget
}

/// Something the reporter shows: once per signature per run.
package protocol LeakFinding: Sendable, CustomStringConvertible {
    var signature: LeakSignature { get }
    /// `verbose` adds what only helps when digging: addresses, every object still alive.
    func text(verbose: Bool) -> String
}

extension LeakFinding {
    package func text(verbose: Bool) -> String { description }
}

/// Two reports with the same signature are the same leak.
package struct LeakSignature: Hashable, Sendable {
    package var typeName: String
    package var kind: LeakKind
    /// The retain cycle's shape (`RetainChain.description`, no addresses) when one was found.
    package var cycle: String? = nil
}

/// What was still alive and detached at T2, for one mark.
package struct LeakReport: LeakFinding {
    package struct Object: Sendable {
        package let typeName: String
        package let path: String
        package let address: UInt
    }

    package let kind: LeakKind
    /// The alive object closest to the root.
    package let leaked: Object
    package let alsoAlive: [Object]
    package let context: LeakContext
    package let markedAt: TimeInterval
    package let detectedAt: TimeInterval
    package var cause: LeakCause? = nil
    /// What the cause was found from, for the DOT and JSON export.
    package var analysis: LeakAnalysis? = nil

    package var signature: LeakSignature {
        var signature = LeakSignature(typeName: leaked.typeName, kind: kind)
        signature.cycle = cause?.chain?.description
        return signature
    }

    static let alsoAliveLimit = 10

    package var description: String { text(verbose: false) }

    /// Who leaked, what of it is still alive, why, and what to change; the rest only when `verbose`.
    package func text(verbose: Bool) -> String {
        let age = String(format: "%.1f", detectedAt - markedAt)
        var lines = ["[TLeakDetector] LEAK \(leaked.typeName) (\(kind.rawValue))"]
        if leaked.path != leaked.typeName { lines.append("  path: \(leaked.path)") }
        if !verbose {
            let owned = alsoAlive.filter { !Self.isViewHierarchy($0.path) }
            lines += owned.prefix(Self.ownedLimit).map { "  also alive: \($0.typeName)  \($0.path)" }
            if owned.count > Self.ownedLimit { lines.append("  also alive: … \(owned.count - Self.ownedLimit) more") }
        }
        if let cause {
            lines += Self.describe(cause, age: age, root: context.rootTypeName, verbose: verbose)
            lines += LeakFixes.suggestions(for: cause).map { "  fix: \($0)" }
        }
        guard verbose else { return lines.joined(separator: "\n") }
        let after = leaked.typeName == context.rootTypeName
            ? context.trigger.rawValue
            : "\(context.trigger.rawValue) of \(context.rootTypeName)"
        lines.append("  still alive \(age)s after \(after), address 0x\(String(leaked.address, radix: 16))")
        if !alsoAlive.isEmpty {
            lines.append("  also alive (\(alsoAlive.count)):")
            lines += alsoAlive.prefix(Self.alsoAliveLimit).map { "    \($0.typeName)  \($0.path)" }
            if alsoAlive.count > Self.alsoAliveLimit {
                lines.append("    … \(alsoAlive.count - Self.alsoAliveLimit) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    static let ownedLimit = 5

    /// A screen alive keeps its views alive: they say nothing about the leak.
    private static func isViewHierarchy(_ path: String) -> Bool {
        path.hasSuffix(".view") || path.contains(".view.") || path.contains("subviews[")
    }

    /// Without a chain there is nothing to act on: what was searched is only worth showing when `verbose`.
    private static func describe(_ cause: LeakCause, age: String, root: String, verbose: Bool) -> [String] {
        switch cause {
        case .cycle(let cycle) where cycle.isCertain:
            return ["  retain cycle: \(inline(cycle))"]
        case .cycle(let cycle):
            return ["  possible retain cycle (? may be weak): \(inline(cycle))"]
        case .heldBy(let holder, let chain):
            guard !chain.nodes.isEmpty else { return ["  held by \(holder)"] }
            return ["  held by \(holder): \(inline(chain))"]
        case .running(let holder):
            return ["  \(holder.subject) is still running \(age)s after \(root) closed"]
        case .noCycle(let searched, 0):
            return verbose ? ["  no retain cycle through it (\(searched) objects searched)"] : []
        case .noCycle(let searched, let partlyRead):
            return verbose ? ["  no retain cycle found through it (\(searched) objects searched, \(partlyRead) objects were only partly read)"] : []
        case .unknown(let limit, let searched):
            return verbose ? ["  retain cycle search stopped at the \(limit.rawValue) limit (\(searched) objects searched)"] : []
        }
    }

    /// `ProfileVC.viewModel → ProfileViewModel.onChange? → ProfileVC`, `?` after a reference not known to be strong.
    private static func inline(_ chain: RetainChain) -> String {
        let steps = chain.nodes.indices.map { index in
            let path = chain.paths[index].steps.isEmpty ? "" : ".\(chain.paths[index])"
            return "\(chain.nodes[index].name)\(path)\(chain.certainties[index] ? "" : "?")"
        }
        return (steps + [chain.end.name]).joined(separator: " → ")
    }
}

/// More instances alive than `LeakInstanceBudget.max`, found when one more registered.
package struct LeakBudgetReport: LeakFinding {
    package let typeName: String
    package let budget: Int
    /// Oldest first: the last one just registered.
    package let alive: [UInt]

    package var signature: LeakSignature { LeakSignature(typeName: typeName, kind: .budget) }

    package var description: String {
        let addresses = alive.suffix(LeakReport.alsoAliveLimit).map { "0x\(String($0, radix: 16))" }
        let skipped = alive.count > LeakReport.alsoAliveLimit ? "… \(alive.count - LeakReport.alsoAliveLimit) older, " : ""
        return [
            "[TLeakDetector] LEAK \(typeName) (budget): \(alive.count) instances alive, budget is \(budget)",
            "  alive (oldest first): \(skipped)\(addresses.joined(separator: ", "))",
        ].joined(separator: "\n")
    }
}

#endif
