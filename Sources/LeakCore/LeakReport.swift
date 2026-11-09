//
//  LeakReport.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

package enum LeakKind: String, Sendable {
    /// The closed screen itself is still alive.
    case screen
    /// The screen is gone but this object is not: something outside the screen holds it.
    case outlived
}

/// Two reports with the same signature are the same leak.
package struct LeakSignature: Hashable, Sendable {
    package let typeName: String
    package let kind: LeakKind
}

/// What was still alive and detached at T2, for one mark.
package struct LeakReport: Sendable, CustomStringConvertible {
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

private extension LeakKind {
    func summary(root: String) -> String {
        switch self {
        case .screen: "the closed screen itself is still alive"
        case .outlived: "\(root) is gone, something outside it still holds this object"
        }
    }
}

#endif
