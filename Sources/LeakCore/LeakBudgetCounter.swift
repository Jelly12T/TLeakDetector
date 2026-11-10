//
//  LeakBudgetCounter.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// Counts live instances of budgeted types. Swift cannot hook every `init`, so instances
/// register themselves; only those matching a budget are kept, weakly.
@MainActor
package final class LeakBudgetCounter {
    private final class Budget {
        let type: AnyClass
        let typeName: String
        let max: Int
        var instances: [Weak] = []

        init(_ budget: LeakInstanceBudget) {
            type = budget.type
            typeName = String(describing: budget.type)
            max = budget.max
        }
    }

    private struct Weak {
        weak var object: AnyObject?
    }

    private let budgets: [Budget]
    private let onOverBudget: @MainActor (LeakBudgetReport) -> Void

    package init(_ budgets: [LeakInstanceBudget], onOverBudget: @escaping @MainActor (LeakBudgetReport) -> Void) {
        self.budgets = budgets.map(Budget.init)
        self.onOverBudget = onOverBudget
    }

    package func aliveCount(of type: AnyClass) -> Int? {
        budgets.first { $0.type === type }.map { $0.instances.count { $0.object != nil } }
    }

    package func track(_ object: AnyObject) {
        guard !budgets.isEmpty else { return }
        let superclasses = superclasses(of: type(of: object)).map(ObjectIdentifier.init)
        for budget in budgets where superclasses.contains(ObjectIdentifier(budget.type)) {
            budget.instances.removeAll { $0.object == nil }
            guard !budget.instances.contains(where: { $0.object === object }) else { continue }
            budget.instances.append(Weak(object: object))
            guard budget.instances.count > budget.max else { continue }

            let alive = budget.instances.compactMap(\.object)
            let report = LeakBudgetReport(typeName: budget.typeName, budget: budget.max,
                                          alive: alive.map { UInt(bitPattern: ObjectIdentifier($0)) })
            withExtendedLifetime(alive) { onOverBudget(report) }
        }
    }
}

#endif
