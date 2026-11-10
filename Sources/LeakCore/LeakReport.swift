//
//  LeakReport.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

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
    package let typeName: String
    package let kind: LeakKind
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

    package var signature: LeakSignature { LeakSignature(typeName: leaked.typeName, kind: kind) }

    static let alsoAliveLimit = 10

    package var description: String {
        let age = String(format: "%.1f", detectedAt - markedAt)
        var lines = [
            "[TLeakDetector] LEAK \(leaked.typeName) (0x\(String(leaked.address, radix: 16))) still alive \(age)s after \(context.trigger.rawValue) of \(context.rootTypeName)",
            "  kind: \(kind.rawValue), \(kind.summary(root: context.rootTypeName))",
            "  path: \(leaked.path)",
        ]
        if !alsoAlive.isEmpty {
            lines.append("  also alive (\(alsoAlive.count)):")
            lines += alsoAlive.prefix(Self.alsoAliveLimit).map { "    \($0.typeName)  \($0.path)" }
            if alsoAlive.count > Self.alsoAliveLimit {
                lines.append("    … \(alsoAlive.count - Self.alsoAliveLimit) more")
            }
        }
        return lines.joined(separator: "\n")
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
