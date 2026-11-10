//
//  LeakBudgetCounterTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Testing
@testable import LeakCore

private class Screen {}
private final class DetailScreen: Screen {}
private final class Unbudgeted {}

@MainActor
private final class BudgetReports {
    var items: [LeakBudgetReport] = []
}

@MainActor
@Suite("Instance budget")
struct LeakBudgetCounterTests {
    private let reports = BudgetReports()

    private func counter(max: Int) -> LeakBudgetCounter {
        let reports = self.reports
        return LeakBudgetCounter([LeakInstanceBudget(Screen.self, max: max)]) { reports.items.append($0) }
    }

    @Test("Budget 1: the second live instance is reported, with both addresses, oldest first")
    func secondInstanceReported() throws {
        let counter = counter(max: 1)
        let first = Screen(), second = Screen()
        counter.track(first)
        #expect(reports.items.isEmpty)

        counter.track(second)
        let report = try #require(reports.items.first)
        #expect(report.signature == LeakSignature(typeName: "Screen", kind: .budget))
        #expect(report.budget == 1)
        #expect(report.alive == [first, second].map { UInt(bitPattern: ObjectIdentifier($0)) })
        #expect(report.description.contains("LEAK Screen: 2 instances alive, budget is 1"))
        withExtendedLifetime((first, second)) {}
    }

    @Test("Instances that died are dropped before counting")
    func deadInstancesDropped() {
        let counter = counter(max: 1)
        do { counter.track(Screen()) }
        let next = Screen()
        counter.track(next)
        #expect(reports.items.isEmpty)
        #expect(counter.aliveCount(of: Screen.self) == 1)
        withExtendedLifetime(next) {}
    }

    @Test("Subclasses count against the base type's budget")
    func subclassesCount() {
        let counter = counter(max: 1)
        let base = Screen(), detail = DetailScreen()
        counter.track(base)
        counter.track(detail)
        #expect(reports.items.map(\.typeName) == ["Screen"])
        withExtendedLifetime((base, detail)) {}
    }

    @Test("The same instance registered twice counts once")
    func registeredTwice() {
        let counter = counter(max: 1)
        let screen = Screen()
        counter.track(screen)
        counter.track(screen)
        #expect(reports.items.isEmpty)
        #expect(counter.aliveCount(of: Screen.self) == 1)
        withExtendedLifetime(screen) {}
    }

    @Test("Types without a budget are not kept")
    func unbudgetedIgnored() {
        let counter = counter(max: 0)
        let other = Unbudgeted()
        counter.track(other)
        #expect(reports.items.isEmpty)
        #expect(counter.aliveCount(of: Unbudgeted.self) == nil)
        withExtendedLifetime(other) {}
    }

    @Test("The counter holds instances weakly")
    func doesNotRetain() {
        let counter = counter(max: 5)
        weak var probe: Screen?
        do {
            let screen = Screen()
            probe = screen
            counter.track(screen)
        }
        #expect(probe == nil)
        #expect(counter.aliveCount(of: Screen.self) == 0)
    }
}

#endif
