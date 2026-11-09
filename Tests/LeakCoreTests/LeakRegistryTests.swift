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

    private func mark(_ object: AnyObject, path: String = "RootVC") {
        registry.expectDeallocation(of: [(object, path)], root: object,
                                    context: LeakContext(trigger: .pop, rootTypeName: "RootVC"))
    }

    // MARK: The 4 scenarios from the spec

    @Test("1. Dies before T1 → no report")
    func diesBeforeT1() {
        do {
            let object = Probe()
            mark(object)
        }
        scheduler.advance(by: 2)
        #expect(registry.pendingCount == 0)
        scheduler.advance(by: 20)
        #expect(reports.isEmpty)
    }

    @Test("2. Alive and detached until T2 → reported once")
    func aliveUntilT2() {
        let object = Probe()
        mark(object, path: "RootVC.viewModel")

        scheduler.advance(by: 2)                       // T1: alive → not conclusive yet
        #expect(reports.isEmpty)
        #expect(registry.stage(of: object) == .waitingT2)

        scheduler.advance(by: 6)                       // T2
        #expect(reports.count == 1)
        #expect(reports.first?.leaked.typeName == "Probe")
        #expect(reports.first?.leaked.path == "RootVC.viewModel")
        #expect(reports.first?.leaked.address == UInt(bitPattern: ObjectIdentifier(object)))
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
        mark(object)
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
        mark(object)
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
        mark(object!)
        scheduler.advance(by: 2)
        #expect(registry.pendingCount == 1)

        object = nil
        scheduler.advance(by: 6)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
    }

    // MARK: One report per mark

    @Test("Screen kept alive: one report headed by the root, the rest listed as also alive")
    func oneReportPerMark() {
        let root = Probe(), view = OtherProbe(), model = OtherProbe()
        registry.expectDeallocation(
            of: [(root, "RootVC"), (view, "RootVC.view"), (model, "RootVC.model")],
            root: root, context: LeakContext(trigger: .dismiss, rootTypeName: "RootVC"))

        scheduler.advance(by: 8)
        #expect(reports.count == 1)
        #expect(reports.first?.kind == .screen)
        #expect(reports.first?.leaked.path == "RootVC")
        #expect(reports.first?.alsoAlive.map(\.path) == ["RootVC.view", "RootVC.model"])
        #expect(registry.pendingCount == 0)
        withExtendedLifetime((root, view, model)) {}
    }

    @Test("Screen died but an object it held did not → outlived, headed by that object")
    func outlived() {
        let model = OtherProbe()
        do {
            let root = Probe()
            registry.expectDeallocation(of: [(root, "RootVC"), (model, "RootVC.model")],
                                        root: root, context: LeakContext(trigger: .pop, rootTypeName: "RootVC"))
        }
        scheduler.advance(by: 8)
        #expect(reports.map(\.kind) == [.outlived])
        #expect(reports.first?.leaked.path == "RootVC.model")
        #expect(reports.first?.alsoAlive.isEmpty == true)
        withExtendedLifetime(model) {}
    }

    @Test("Root back in the hierarchy → whole mark cancelled, objects that cannot attach included")
    func rootReattachedCancelsMark() {
        let root = Probe(), model = OtherProbe()
        registry.expectDeallocation(of: [(root, "RootVC"), (model, "RootVC.model")],
                                    root: root, context: LeakContext(trigger: .pop, rootTypeName: "RootVC"))
        scheduler.advance(by: 2)
        attachment.attached.insert(ObjectIdentifier(root))

        scheduler.advance(by: 6)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
        withExtendedLifetime((root, model)) {}
    }

    @Test("A member moved back into the hierarchy is left out of the report")
    func attachedMemberLeftOut() {
        let root = Probe(), reused = OtherProbe()
        registry.expectDeallocation(of: [(root, "RootVC"), (reused, "RootVC.view.subviews[0]")],
                                    root: root, context: LeakContext(trigger: .pop, rootTypeName: "RootVC"))
        attachment.attached.insert(ObjectIdentifier(reused))

        scheduler.advance(by: 8)
        #expect(reports.first?.leaked.path == "RootVC")
        #expect(reports.first?.alsoAlive.isEmpty == true)
        withExtendedLifetime((root, reused)) {}
    }

    @Test("Sibling screens in a cycle, closed together: each is reported by its own mark", arguments: [false, true])
    func siblingRootsKeepTheirMark(reversed: Bool) {
        let level2 = Probe(), level3 = OtherProbe()
        let marks: [(root: AnyObject, path: String, other: AnyObject, otherPath: String)] = [
            (level2, "Level2", level3, "Level2.nextLevel"),
            (level3, "Level3", level2, "Level3.previousLevel"),
        ]
        for mark in reversed ? marks.reversed() : marks {
            registry.expectDeallocation(
                of: [(mark.root, mark.path), (mark.other, mark.otherPath)], root: mark.root,
                context: LeakContext(trigger: .pop, rootTypeName: mark.path))
        }
        scheduler.advance(by: 8)
        #expect(Set(reports.map(\.leaked.path)) == ["Level2", "Level3"])
        #expect(reports.allSatisfy { $0.alsoAlive.isEmpty && $0.kind == .screen })
        withExtendedLifetime((level2, level3)) {}
    }

    // MARK: The registry must not keep objects alive

    @Test("Registry holds objects weakly: dropping the last outside ref deallocates immediately")
    func doesNotRetain() {
        weak var probe: Probe?
        do {
            let object = Probe()
            probe = object
            mark(object)
            #expect(probe != nil)
        }
        #expect(probe == nil)               // before any timer fired
        #expect(registry.pendingCount == 1) // expectation still there, holding nothing
        scheduler.advance(by: 8)
        #expect(reports.isEmpty)
        #expect(registry.pendingCount == 0)
    }

    // MARK: De-duplication

    @Test("Marking again moves the object to the new mark and restarts its timers")
    func remarkRestartsTimers() {
        let object = Probe()
        mark(object, path: "first")
        scheduler.advance(by: 1.5)
        mark(object, path: "second")
        #expect(registry.pendingCount == 1)

        scheduler.advance(by: 1)            // t=2.5: old T1 ignored, new T1 is at 3.5
        #expect(registry.stage(of: object) == .waitingT1)

        scheduler.advance(by: 6)            // t=8.5: old T2 would have been at 8 → must not fire
        #expect(reports.isEmpty)

        scheduler.advance(by: 1)            // t=9.5 = 1.5 + 8
        #expect(reports.map(\.leaked.path) == ["second"])
        withExtendedLifetime(object) {}
    }

    @Test("Address reused by a new object → fresh expectation, old timers ignored")
    func addressReuse() throws {
        var keep: [ReuseProbe] = []
        var reused: ReuseProbe?
        // The allocator usually hands the same address to the next same-size object, but not
        // always when other suites allocate in parallel: retry from a clean registry.
        for _ in 0..<5 where reused == nil {
            scheduler.advance(by: 10)
            var oldID: ObjectIdentifier?
            do {
                let old = ReuseProbe()
                oldID = ObjectIdentifier(old)
                mark(old, path: "old")
            }
            scheduler.advance(by: 1)
            for _ in 0..<1_000 {
                let candidate = ReuseProbe()
                if ObjectIdentifier(candidate) == oldID { reused = candidate; break }
                keep.append(candidate)
            }
        }
        let newObject = try #require(reused, "allocator did not reuse the address; nothing to test")

        mark(newObject, path: "new")
        #expect(registry.pendingCount == 1)
        #expect(registry.expectation(for: newObject)?.path == "new")

        scheduler.advance(by: 1.5)          // old T1 (t=2) must not touch the new expectation
        #expect(registry.stage(of: newObject) == .waitingT1)

        scheduler.advance(by: 7.5)          // t=10; new T2 was due at 1 + 8 = 9
        #expect(reports.map(\.leaked.path) == ["new"])
        withExtendedLifetime((newObject, keep)) {}
    }

    @Test("Type name is captured at mark time")
    func typeNameCaptured() {
        let a = Probe(), b = OtherProbe()
        mark(a)
        mark(b)
        scheduler.advance(by: 8)
        #expect(Set(reports.map(\.leaked.typeName)) == ["Probe", "OtherProbe"])
        withExtendedLifetime((a, b)) {}
    }
}

/// Odd size, so objects from suites running in parallel do not take the freed address.
private final class ReuseProbe {
    let payload: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

@MainActor
private final class ReportBox {
    var reports: [LeakReport] = []
}

#endif
