//
//  LeakConfigurationTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import Testing
@testable import LeakCore

private class CachedScreen {}
private final class CachedDetailScreen: CachedScreen {}
private final class PlainScreen {}
private final class OptedOutScreen: LeakOptOut {}

@Suite("LeakConfiguration")
struct LeakConfigurationTests {
    @Test("Defaults: T1 2s, T2 8s, mode from the debugger, no depth limit, nothing allowed")
    func defaults() {
        let configuration = LeakConfiguration(suppressionFile: nil)
        #expect(configuration.t1 == 2)
        #expect(configuration.t2 == 8)
        #expect(configuration.mode == nil)
        #expect(configuration.maxSubtreeDepth == nil)
        #expect(!configuration.isExempt(PlainScreen.self))
    }

    @Test("Allowlist covers the type and its subclasses, nothing else")
    func allowlist() {
        let isExempt = LeakConfiguration(allowedTypes: [CachedScreen.self], suppressionFile: nil).isExempt
        #expect(isExempt(CachedScreen.self))
        #expect(isExempt(CachedDetailScreen.self))
        #expect(!isExempt(PlainScreen.self))
    }

    @Test("LeakOptOut conformers are exempt without being listed")
    func optOut() {
        #expect(LeakConfiguration(suppressionFile: nil).isExempt(OptedOutScreen.self))
    }
}

@Suite("Suppression file")
struct LeakSuppressionFileTests {
    private let hanoi = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    private func parse(_ entries: [Any], version: Any = 1) -> LeakSuppressionFile.Loaded {
        let data = try! JSONSerialization.data(withJSONObject: ["version": version, "suppressions": entries])
        return LeakSuppressionFile.parse(data, source: "LeakSuppressions.json", timeZone: hanoi)
    }

    private func entry(_ type: String, kind: String = "screen", expires: String = "2026-12-31") -> [String: Any] {
        ["signature": ["type": type, "kind": kind], "reason": "Cached on purpose", "owner": "thachlh", "expires": expires]
    }

    @Test("A valid entry: signature, reason, owner, and the expiry day included")
    func validEntry() throws {
        let loaded = parse([entry("ProfileVC")])
        #expect(loaded.problems.isEmpty)
        let suppression = try #require(loaded.suppressions.first)
        #expect(suppression.signature == LeakSignature(typeName: "ProfileVC", kind: .screen))
        #expect(suppression.reason == "Cached on purpose")
        #expect(suppression.owner == "thachlh")
        #expect(suppression.expires == "2026-12-31")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hanoi
        #expect(suppression.endsAt == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
    }

    @Test("Broken entries are skipped one by one with the reason, valid ones are kept")
    func brokenEntries() {
        var noReason = entry("B"); noReason["reason"] = nil
        var emptyOwner = entry("C"); emptyOwner["owner"] = "  "
        var noSignature = entry("G"); noSignature["signature"] = nil
        let loaded = parse([entry("A"), noReason, emptyOwner, entry("D", kind: "rooted"),
                            entry("E", expires: "2026-02-30"), 42, noSignature])

        #expect(loaded.suppressions.map(\.signature.typeName) == ["A"])
        #expect(loaded.problems == [
            #"LeakSuppressions.json: suppressions[1] (B): missing "reason", entry ignored"#,
            #"LeakSuppressions.json: suppressions[2] (C): "owner" must be a non-empty string, entry ignored"#,
            #"LeakSuppressions.json: suppressions[3] (D): "kind" is "rooted", expected one of screen, outlived, entry ignored"#,
            #"LeakSuppressions.json: suppressions[4] (E): "expires" is "2026-02-30", expected a date like 2026-12-31, entry ignored"#,
            #"LeakSuppressions.json: suppressions[5]: must be an object, entry ignored"#,
            #"LeakSuppressions.json: suppressions[6]: missing "signature": {"type": ..., "kind": ...}, entry ignored"#,
        ])
    }

    @Test("Not JSON, wrong shape, unknown version: the whole file is ignored with the reason")
    func brokenFile() throws {
        let notJSON = LeakSuppressionFile.parse(Data("{ suppressions: [".utf8), source: "LeakSuppressions.json")
        #expect(notJSON.suppressions.isEmpty)
        #expect(try #require(notJSON.problems.first).hasPrefix("LeakSuppressions.json: not valid JSON ("))

        let array = LeakSuppressionFile.parse(Data("[]".utf8), source: "LeakSuppressions.json")
        #expect(array.problems == [#"LeakSuppressions.json: expected {"version": 1, "suppressions": [...]}, file ignored"#])

        let future = parse([entry("A")], version: 2)
        #expect(future.suppressions.isEmpty)
        #expect(future.problems == ["LeakSuppressions.json: unsupported version 2, expected 1, file ignored"])
    }

    @Test("A file that cannot be read is reported, not thrown")
    func missingFile() {
        let loaded = LeakSuppressionFile.load(URL(fileURLWithPath: "/nonexistent/LeakSuppressions.json"))
        #expect(loaded.suppressions.isEmpty)
        #expect(loaded.problems == ["LeakSuppressions.json: cannot be read, file ignored"])
    }
}

#endif
