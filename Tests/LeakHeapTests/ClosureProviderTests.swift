//
//  ClosureProviderTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Combine
import Foundation
import Testing
import LeakGraph
@testable import LeakHeap

private final class Item {}

private final class Runner {
    var run: () -> Void = {}
}

private func makeGeneric<T>(_ value: T, _ count: Int) -> () -> Void {
    { _ = (value, count) }
}

private final class Mirrored: CustomReflectable {
    var item = Item()
    var customMirror: Mirror { Mirror(self, children: []) }
}

private final class Feed {
    let refresh = PassthroughSubject<Void, Never>()
    var cancellables = Set<AnyCancellable>()

    func subscribe() {
        refresh.sink { self.reload() }.store(in: &cancellables)
    }

    func reload() {}
}

@Suite("Closure provider")
struct ClosureProviderTests {
    @Test("A closure made in a generic function: captures typed from the context's own generic arguments")
    func genericClosure() throws {
        let item = Item(), runner = Runner()
        runner.run = makeGeneric(item, 3)
        let context = try #require(references(of: runner).first { $0.path == "run" })
        guard case .closure(let function) = context.kind else { Issue.record("not a closure: \(context.kind)"); return }
        #expect(function.contains("makeGeneric"))
        let captures = references(of: context.target)
        #expect(captures.map(\.path) == ["capture 0"])
        #expect(captures.first?.object === item)
        #expect(captures.first?.certain == true)
    }

    @Test("A custom mirror does not hide stored properties: fields are read where the runtime lays them out")
    func customMirror() {
        let mirrored = Mirrored()
        let found = references(of: mirrored)
        #expect(found.map(\.path) == ["item"])
        #expect(found.first?.object === mirrored.item)
        #expect(found.first?.certain == true)
    }

    @Test("Combine: a sink closure capturing its owner closes a certain cycle through AnyCancellable and Sink")
    func combineSink() throws {
        let feed = Feed()
        feed.subscribe()
        defer { feed.cancellables.removeAll() }
        let found = try #require(cycle(through: feed))
        #expect(found.isCertain)
        #expect(found.description.contains("AnyCancellable.storage.cancellable → Subscribers.Sink"))
        #expect(found.description.hasSuffix("→ Feed"))
    }

    @Test("Pointees include weak references: what a closure points to at all")
    func pointees() {
        let item = Item(), other = Item(), runner = Runner()
        runner.run = { [weak item, other] in _ = (item, other) }
        let found = LiveHeap().pointees(of: .object(runner), depth: 3)
        #expect(found.contains { $0 === item })
        #expect(found.contains { $0 === other })
    }
}

#endif
