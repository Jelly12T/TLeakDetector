//
//  LeakRegistryTests.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Testing
@testable import LeakCore

@MainActor
@Suite("LeakRegistry T1/T2")
struct LeakRegistryTests {
    let scheduler = ManualScheduler()
    let attachment = FakeAttachment()
    var reports: [LeakReport] { box.reports }
    private let box = ReportBox()
    let registry: LeakRegistry

    init() {
        let box = self.box
        registry = LeakRegistry(scheduler: scheduler, attachment: attachment,
                                configuration: .init(t1: 2, t2: 8)) { box.reports.append($0) }
    }

    private func context(_ path: String = "Root") -> LeakContext {
        LeakContext(trigger: .pop, rootTypeName: "RootVC", path: path)
    }

    // MARK: The 4 scenarios from the spec

    @Test("1. Dies before T1 → no report")
    func diesBeforeT1() {
        do {
            let object = Probe()
            registry.expectDeallocation(of: object, context: context())
        }
        scheduler.advance(by: 2)
        #expect(registry.pendingCount == 0)
        scheduler.advance(by: 20)
        #expect(reports.isEmpty)
    }

    @Test("2. Alive and detached until T2 → reported once")
    func aliveUntilT2() {
        let object = Probe()
        registry.expectDeallocation(of: object, context: context("RootVC.viewModel"))

        scheduler.advance(by: 2)                       // T1: alive → not conclusive yet
        #expect(reports.isEmpty)
        #expect(registry.expectation(for: object)?.stage == .waitingT2)

        scheduler.advance(by: 6)                       // T2
        #expect(reports.count == 1)
        #expect(reports.first?.typeName == "Probe")
        #expect(reports.first?.context.path == "RootVC.viewModel")
        #expect(reports.first?.context.trigger == .pop)
        #expect(reports.first.map { $0.detectedAt - $0.markedAt } == 8)

        scheduler.advance(by: 100)                     // never reported twice
        #expect(reports.count == 1)
        #expect(registry.pendingCount == 0)
        withExtendedLifetime(object) {}
    }

    @Test("3a. Re-attached before T1 → cancelled")
    func reattachedBeforeT1() {
        let object = Probe()
        registry.expectDeallocation(of: object, context: context())
        attachment.attached.insert(ObjectIdentifier(object))

        scheduler.advance(by: 2)
        #expect(registry.pendingCount == 0)
        scheduler.advance(by: 20)
        #expect(reports.isEmpty)
        withExtendedLifetime(object) {}
    }

    @Test("3b. Re-attached between T1 and T2 → cancelled at T2")
    func reattachedBetweenT1AndT2() {
        let object = Probe()
        registry.expectDeallocation(of: object, context: context())
        scheduler.advance(by: 2)
        attachment.attached.insert(ObjectIdentifier(object))

        scheduler.advance(by: 6)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
        withExtendedLifetime(object) {}
    }

    @Test("4. Dies between T1 and T2 → no report")
    func diesBetweenT1AndT2() {
        var object: Probe? = Probe()
        registry.expectDeallocation(of: object!, context: context())
        scheduler.advance(by: 2)
        #expect(registry.pendingCount == 1)

        object = nil
        scheduler.advance(by: 6)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
    }

    // MARK: The registry must not keep objects alive

    @Test("Registry holds objects weakly: dropping the last outside ref deallocates immediately")
    func doesNotRetain() {
        weak var probe: Probe?
        do {
            let object = Probe()
            probe = object
            registry.expectDeallocation(of: object, context: context())
            #expect(probe != nil)
        }
        #expect(probe == nil)               // before any timer fired
        #expect(registry.pendingCount == 1) // expectation still there, holding nothing
        scheduler.advance(by: 8)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
    }

    // MARK: De-duplication

    @Test("Marking again keeps one expectation and restarts the timers")
    func remarkRestartsTimers() {
        let object = Probe()
        registry.expectDeallocation(of: object, context: context("first"))
        scheduler.advance(by: 1.5)
        registry.expectDeallocation(of: object, context: context("second"))
        #expect(registry.pendingCount == 1)

        scheduler.advance(by: 1)            // t=2.5: old T1 ignored, new T1 is at 3.5
        #expect(registry.expectation(for: object)?.stage == .waitingT1)

        scheduler.advance(by: 6)            // t=8.5: old T2 would have been at 8 → must not fire
        #expect(reports.isEmpty)

        scheduler.advance(by: 1)            // t=9.5 = 1.5 + 8
        #expect(reports.count == 1)
        #expect(reports.first?.context.path == "second")
        withExtendedLifetime(object) {}
    }

    @Test("Address reused by a new object → fresh expectation, old timers ignored")
    func addressReuse() throws {
        var oldID: ObjectIdentifier?
        do {
            let old = Probe()
            oldID = ObjectIdentifier(old)
            registry.expectDeallocation(of: old, context: context("old"))
        }
        scheduler.advance(by: 1)

        // The allocator usually hands the same address to the next same-size object.
        var keep: [Probe] = []
        var reused: Probe?
        for _ in 0..<1_000 {
            let candidate = Probe()
            if ObjectIdentifier(candidate) == oldID { reused = candidate; break }
            keep.append(candidate)
        }
        let newObject = try #require(reused, "allocator did not reuse the address; nothing to test")

        registry.expectDeallocation(of: newObject, context: context("new"))
        #expect(registry.pendingCount == 1)
        #expect(registry.expectation(for: newObject)?.context.path == "new")

        scheduler.advance(by: 1.5)          // old T1 (t=2) must not touch the new expectation
        #expect(registry.expectation(for: newObject)?.stage == .waitingT1)

        scheduler.advance(by: 7.5)          // t=10; new T2 was due at 1 + 8 = 9
        #expect(reports.map(\.context.path) == ["new"])
        withExtendedLifetime((newObject, keep)) {}
    }

    @Test("Type name is captured at mark time")
    func typeNameCaptured() {
        let a = Probe(), b = OtherProbe()
        registry.expectDeallocation(of: a, context: context())
        registry.expectDeallocation(of: b, context: context())
        scheduler.advance(by: 8)
        #expect(Set(reports.map(\.typeName)) == ["Probe", "OtherProbe"])
        withExtendedLifetime((a, b)) {}
    }
}

@MainActor
private final class ReportBox {
    var reports: [LeakReport] = []
}

#endif
