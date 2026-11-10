//
//  LeakReporterTests.swift
//  TLeakDetector
//
//  Created by thachlh on 9/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import os
import Testing
@testable import LeakCore

@MainActor
private final class EffectRecorder {
    var debuggerAttached = false
    var now = Date(timeIntervalSince1970: 0)
    private(set) var events: [String] = []
    private(set) var logs: [(level: OSLogType, text: String)] = []

    var effects: LeakReporter.Effects {
        LeakReporter.Effects(
            log: { self.logs.append(($0, $1)); self.events.append("log") },
            now: { self.now },
            isDebuggerAttached: { self.debuggerAttached },
            breakIntoDebugger: { self.events.append("break") },
            crash: { _ in self.events.append("crash") })
    }
}

private func report(
    _ typeName: String = "ProfileVC",
    kind: LeakKind = .screen,
    alsoAlive: [LeakReport.Object] = []
) -> LeakReport {
    LeakReport(
        kind: kind,
        leaked: .init(typeName: typeName, path: typeName, address: 0xbeef),
        alsoAlive: alsoAlive,
        context: LeakContext(trigger: .pop, rootTypeName: "ProfileVC"),
        markedAt: 10,
        detectedAt: 18.04)
}

@MainActor
@Suite("LeakReporter")
struct LeakReporterTests {
    private let recorder = EffectRecorder()

    @Test("Default mode: debugger attached → pause, not attached → crash; checked at each report")
    func defaultMode() {
        let reporter = LeakReporter(effects: recorder.effects)
        recorder.debuggerAttached = true
        reporter.report(report("A"))
        recorder.debuggerAttached = false
        reporter.report(report("B"))
        #expect(recorder.events == ["log", "break", "log", "crash"])
    }

    @Test("Forced modes ignore the debugger", arguments: [
        (LeakReportMode.log, ["log"]),
        (.debugger, ["log", "break"]),
        (.crash, ["log", "crash"]),
    ])
    func forcedModes(mode: LeakReportMode, expected: [String]) {
        recorder.debuggerAttached = mode != .debugger
        LeakReporter(mode: mode, effects: recorder.effects).report(report())
        #expect(recorder.events == expected)
    }

    @Test("Same type and kind twice → reported once; another kind or type → reported again")
    func dedupBySignature() {
        let reporter = LeakReporter(mode: .log, effects: recorder.effects)
        reporter.report(report("ProfileVC"))
        reporter.report(report("ProfileVC"))
        reporter.report(report("ProfileVC", kind: .outlived))
        reporter.report(report("SettingsVC"))
        #expect(recorder.logs.count == 3)
    }

    @Test("Report says what leaked, after which leave event, for how long, and what else is alive")
    func content() throws {
        let others = (0..<12).map { LeakReport.Object(typeName: "UILabel", path: "ProfileVC.view.subviews[\($0)]", address: 0) }
        LeakReporter(mode: .log, effects: recorder.effects).report(report(alsoAlive: others))
        let text = try #require(recorder.logs.first).text
        #expect(text.contains("LEAK ProfileVC (0xbeef) still alive 8.0s after pop of ProfileVC"))
        #expect(text.contains("kind: screen"))
        #expect(text.contains("also alive (12):"))
        #expect(text.contains("UILabel  ProfileVC.view.subviews[9]"))
        #expect(!text.contains("subviews[10]"))
        #expect(text.contains("… 2 more"))
    }

    @Test("Pausing tells the developer how to resume")
    func pauseHint() throws {
        LeakReporter(mode: .debugger, effects: recorder.effects).report(report())
        #expect(try #require(recorder.logs.first).text.hasSuffix("Continue to resume."))
    }

    // MARK: Suppressions

    private func suppression(kind: LeakKind = .screen) -> LeakSuppression {
        LeakSuppression(signature: LeakSignature(typeName: "ProfileVC", kind: kind),
                        reason: "Cached on purpose", owner: "thachlh",
                        expires: "2026-12-31", endsAt: Date(timeIntervalSince1970: 100))
    }

    @Test("Suppressed leak: logged once as a notice, never pauses or crashes")
    func suppressed() throws {
        recorder.now = Date(timeIntervalSince1970: 99)
        let reporter = LeakReporter(mode: .crash, suppressions: [suppression()], effects: recorder.effects)
        reporter.report(report())
        reporter.report(report())
        #expect(recorder.events == ["log"])
        let log = try #require(recorder.logs.first)
        #expect(log.level == .default)
        #expect(log.text.contains("suppressed until 2026-12-31: Cached on purpose (owner: thachlh)"))
    }

    @Test("Expired suppression: reported like a new leak, saying which entry expired")
    func expired() throws {
        recorder.now = Date(timeIntervalSince1970: 100)
        LeakReporter(mode: .crash, suppressions: [suppression()], effects: recorder.effects).report(report())
        #expect(recorder.events == ["log", "crash"])
        let log = try #require(recorder.logs.first)
        #expect(log.level == .error)
        #expect(log.text.contains("suppression expired on 2026-12-31: Cached on purpose (owner: thachlh)"))
    }

    @Test("Budget findings go through the same reporter, deduplicated by their own signature")
    func budgetFinding() {
        let reporter = LeakReporter(mode: .log, effects: recorder.effects)
        let budget = LeakBudgetReport(typeName: "ProfileVC", budget: 1, alive: [0xa, 0xb])
        reporter.report(budget)
        reporter.report(budget)
        reporter.report(report("ProfileVC"))
        #expect(recorder.logs.count == 2)
        #expect(recorder.logs.first?.text.contains("kind: budget") == true)
        #expect(recorder.logs.first?.text.contains("alive (oldest first): 0xa, 0xb") == true)
    }

    @Test("A suppression covers its own signature only")
    func otherSignature() {
        LeakReporter(mode: .crash, suppressions: [suppression(kind: .outlived)], effects: recorder.effects)
            .report(report())
        #expect(recorder.events == ["log", "crash"])
    }
}

#endif
