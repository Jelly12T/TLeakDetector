//
//  PatternChecker.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakCore
import LeakGraph
import LeakHeap

/// Classic patterns among what a closing screen must release, found before T1: a warning says what will
/// keep the screen alive, even if, this time, something else releases it later.
@MainActor
package enum PatternChecker {
    /// A block reaching a member farther than this is not worth a warning: the graph will say more at T1.
    private static let blockLimits = RetainCycleSearch.Limits(maxDepth: 4, maxNodes: 64)

    package static func warnings(
        members: [(object: AnyObject, path: String)],
        context: LeakContext,
        holds: FrameworkHolds = .shared
    ) -> [LeakWarning] {
        var warnings: [LeakWarning] = []
        let byID = Dictionary(members.map { (ObjectIdentifier($0.object), $0) }, uniquingKeysWith: { first, _ in first })

        func warn(_ pattern: LeakPattern, _ member: (object: AnyObject, path: String), _ detail: String, fix: String) {
            warnings.append(LeakWarning(pattern: pattern, typeName: typeName(member.object), detail: detail, fix: fix, context: context))
        }

        for member in members where SymbolNames.isAppClass(type(of: member.object)) {
            for reference in LiveHeap().strongReferences(from: .object(member.object)) where reference.isCertain {
                guard case .field(let raw)? = reference.path.steps.first, reference.path.steps.count == 1,
                      case .object(let target) = reference.target else { continue }
                let field = LeakFixes.stripped(raw)
                guard LeakFixes.isDelegateName(field) else { continue }
                let owner = typeName(member.object)
                warn(.strongDelegate, member, "\(owner).\(field) holds \(typeName(target)) strongly",
                     fix: LeakFixes.weakDelegateFix(owner, raw))
            }
        }

        for hold in holds.all where hold.isActive {
            guard let referent = hold.referent else { continue }
            if let member = byID[ObjectIdentifier(referent)] {
                let subject = "\(typeName(referent)) (\(member.path))"
                switch hold.kind {
                case .timerTarget:
                    warn(.timerTarget, member, "a scheduled Timer targets \(subject)", fix: LeakFixes.fix(for: .timer))
                case .displayLink:
                    warn(.displayLinkTarget, member, "a CADisplayLink targets \(subject)", fix: LeakFixes.fix(for: .displayLink))
                case .urlSession:
                    warn(.urlSessionDelegate, member, "a URLSession has \(subject) as its delegate", fix: LeakFixes.fix(for: .urlSession))
                case .scriptMessageHandler:
                    warn(.scriptMessageHandler, member,
                         "WKUserContentController holds \(subject) as script message handler \"\(hold.name)\"",
                         fix: LeakFixes.scriptMessageHandlerFix)
                case .timerBlock, .observer:
                    break
                }
            } else if hold.kind == .timerBlock || hold.kind == .observer,
                      let member = firstMember(reachedFrom: referent, in: byID) {
                let subject = "\(typeName(member.object)) (\(member.path))"
                if hold.kind == .timerBlock {
                    warn(.timerTarget, member, "a scheduled Timer's block holds \(subject) strongly", fix: LeakFixes.fix(for: .timer))
                } else {
                    let name = hold.name.isEmpty ? "every notification" : hold.name
                    warn(.observerBlock, member, "a NotificationCenter observer for \(name) holds \(subject) strongly in its block",
                         fix: LeakFixes.fix(for: .notificationObserver))
                }
            }
        }
        return warnings
    }

    /// The member a block holds strongly through a short chain, if any.
    private static func firstMember(reachedFrom block: AnyObject,
                                    in members: [ObjectIdentifier: (object: AnyObject, path: String)]) -> (object: AnyObject, path: String)? {
        let goals = Set(members.keys.map { UInt(bitPattern: $0) })
        let search = LiveHeap().shortestChain(from: [.object(block)], to: goals, limits: blockLimits)
        guard case .found(let chain) = search.outcome, chain.isCertain else { return nil }
        return members[ObjectIdentifier(chain.end.id)]
    }

    private static func typeName(_ object: AnyObject) -> String {
        String(describing: type(of: object))
    }
}

private extension ObjectIdentifier {
    init(_ id: UInt) {
        self = unsafeBitCast(id, to: ObjectIdentifier.self)
    }
}

#endif
