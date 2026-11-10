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

    package var description: String {
        let age = String(format: "%.1f", detectedAt - markedAt)
        var lines = [
            "[TLeakDetector] LEAK \(leaked.typeName) (0x\(String(leaked.address, radix: 16))) still alive \(age)s after \(context.trigger.rawValue) of \(context.rootTypeName)",
            "  kind: \(kind.rawValue), \(kind.summary(root: context.rootTypeName))",
            "  path: \(leaked.path)",
        ]
        // The cause first: a long list of objects alive must not push it out of a truncated log line.
        if let cause {
            lines += Self.describe(cause, age: age, root: context.rootTypeName)
            lines += LeakFixes.suggestions(for: cause).map { "  fix: \($0)" }
        }
        if !alsoAlive.isEmpty {
            lines.append("  also alive (\(alsoAlive.count)):")
            lines += alsoAlive.prefix(Self.alsoAliveLimit).map { "    \($0.typeName)  \($0.path)" }
            if alsoAlive.count > Self.alsoAliveLimit {
                lines.append("    … \(alsoAlive.count - Self.alsoAliveLimit) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ cause: LeakCause, age: String, root: String) -> [String] {
        switch cause {
        case .cycle(let cycle):
            let header = cycle.isCertain
                ? "  retain cycle (certain):"
                : "  possible retain cycle (references marked ? are not known to be strong):"
            return [header] + steps(of: cycle)
        case .heldBy(let holder, let chain):
            guard !chain.nodes.isEmpty else { return ["  held by \(holder)"] }
            return ["  held by \(holder):"] + steps(of: chain)
        case .running(let holder):
            return ["  \(holder.subject) is still running \(age)s after \(root) closed"]
        case .noCycle(let searched, 0):
            return ["  no retain cycle through it (\(searched) objects searched): something outside the screen holds it,",
                    "  e.g. a timer, an observer, a task or a singleton"]
        case .noCycle(let searched, let partlyRead):
            return ["  no retain cycle found through it (\(searched) objects searched, \(partlyRead) only partly read): probably held",
                    "  from outside the screen, but a cycle through the partly read ones cannot be ruled out"]
        case .unknown(let limit, let searched):
            return ["  retain cycle search stopped at the \(limit.rawValue) limit (\(searched) objects searched)"]
        }
    }

    private static func steps(of chain: RetainChain) -> [String] {
        chain.nodes.indices.map { index in
            let mark = chain.certainties[index] ? "" : " ?"
            let path = chain.paths[index].steps.isEmpty ? "" : ".\(chain.paths[index])"
            return "    \(chain.nodes[index].name)\(path) → \(chain.target(of: index).name)\(mark)"
        }
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
            "[TLeakDetector] LEAK \(typeName): \(alive.count) instances alive, budget is \(budget)",
            "  kind: budget, \(LeakKind.budget.summary(root: typeName))",
            "  alive (oldest first): \(skipped)\(addresses.joined(separator: ", "))",
        ].joined(separator: "\n")
    }
}

private extension LeakKind {
    func summary(root: String) -> String {
        switch self {
        case .screen: "the closed screen itself is still alive"
        case .outlived: "\(root) is gone, something outside it still holds this object"
        case .budget: "more instances alive at once than its budget"
        }
    }
}

#endif
