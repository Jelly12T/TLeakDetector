//
//  RetainCycleSearchTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import Testing
@testable import LeakGraph

/// Builds a graph by name: objects unless declared otherwise; ids follow the order names first appear.
private struct Sketch {
    var graph = RetainGraph()
    private var ids: [String: RetainGraph.Node.ID] = [:]

    @discardableResult
    mutating func node(_ name: String, module: String? = "App") -> RetainGraph.Node.ID {
        add(name, kind: .object(type: name, module: module))
    }

    @discardableResult
    mutating func closure(_ function: String) -> RetainGraph.Node.ID {
        add(function, kind: .closure(function: function))
    }

    private mutating func add(_ name: String, kind: RetainGraph.Node.Kind) -> RetainGraph.Node.ID {
        if let id = ids[name] { return id }
        let id = UInt(ids.count + 1)
        ids[name] = id
        graph.add(RetainGraph.Node(id: id, kind: kind))
        return id
    }

    mutating func edge(_ from: String, _ field: String, _ to: String, certain: Bool = true) {
        edge(from, RetainPath([.field(field)]), to, certain: certain)
    }

    mutating func edge(_ from: String, _ path: RetainPath, _ to: String, certain: Bool = true) {
        let source = node(from), target = node(to)
        graph.addEdge(from: source, to: target, path: path, isCertain: certain)
    }

    mutating func search(
        from name: String = "Screen",
        limits: RetainCycleSearch.Limits = .init(),
        pruning modules: Set<String> = []
    ) -> RetainCycleSearch {
        graph.shortestCycle(through: node(name), limits: limits, prunedModules: modules)
    }

    mutating func holders(of goal: String, from roots: [String]) -> RetainCycleSearch {
        let goalID = node(goal)
        return graph.shortestChain(from: roots.map { node($0) }, to: [goalID])
    }
}

private func cycle(_ search: RetainCycleSearch) -> String? {
    if case .found(let cycle) = search.outcome { return cycle.description }
    return nil
}

@Suite("Shortest retain cycle")
struct RetainCycleSearchTests {
    @Test("Two cycles through the object: the shorter one is found")
    func shortestWins() {
        var sketch = Sketch()
        sketch.edge("Screen", "worker", "Worker")
        sketch.edge("Worker", "callback", "Closure")
        sketch.edge("Closure", "self", "Screen")
        sketch.edge("Screen", "delegate", "Delegate")
        sketch.edge("Delegate", "owner", "Screen")
        #expect(cycle(sketch.search()) == "Screen.delegate → Delegate.owner → Screen")
    }

    @Test("Equally short cycles: the first reference in source order wins, so the shape is stable")
    func tieFollowsSourceOrder() {
        var sketch = Sketch()
        sketch.edge("Screen", "first", "A")
        sketch.edge("Screen", "second", "B")
        sketch.edge("B", "back", "Screen")
        sketch.edge("A", "back", "Screen")
        #expect(cycle(sketch.search()) == "Screen.first → A.back → Screen")
    }

    @Test("An object holding itself is a cycle of length 1")
    func selfReference() throws {
        var sketch = Sketch()
        sketch.edge("Screen", "me", "Screen")
        guard case .found(let found) = sketch.search().outcome else { Issue.record("no cycle"); return }
        #expect(found.length == 1)
        #expect(found.description == "Screen.me → Screen")
    }

    @Test("No path back: not found, and everything reachable was explored")
    func noCycle() {
        var sketch = Sketch()
        sketch.edge("Screen", "view", "View")
        sketch.edge("View", "label", "Label")
        sketch.edge("Screen", "model", "Model")
        let search = sketch.search()
        #expect(search.outcome == .notFound)
        #expect(search.explored.nodes.count == 4)
        #expect(search.explored.edgeCount == 3)
    }

    @Test("A cycle that does not go through the object does not count")
    func cycleElsewhere() {
        var sketch = Sketch()
        sketch.edge("Screen", "model", "Model")
        sketch.edge("Model", "cache", "Cache")
        sketch.edge("Cache", "owner", "Model")
        #expect(sketch.search().outcome == .notFound)
    }

    @Test("A cycle longer than maxDepth: inconclusive, found once the limit allows it")
    func depthLimit() {
        var sketch = Sketch()
        sketch.edge("Screen", "a", "A")
        sketch.edge("A", "b", "B")
        sketch.edge("B", "c", "C")
        sketch.edge("C", "screen", "Screen")
        #expect(sketch.search(limits: .init(maxDepth: 3)).outcome == .inconclusive(.depth))
        #expect(cycle(sketch.search(limits: .init(maxDepth: 4))) == "Screen.a → A.b → B.c → C.screen → Screen")
    }

    @Test("Too many objects: stops at maxNodes, inconclusive")
    func nodeLimit() {
        var sketch = Sketch()
        for index in 0..<10 { sketch.edge("Screen", "item\(index)", "Item\(index)") }
        let search = sketch.search(limits: .init(maxNodes: 5))
        #expect(search.outcome == .inconclusive(.nodes))
        #expect(search.explored.nodes.count == 5)
    }

    @Test("Node limit hit, but an object already queued leads back: the cycle is still found")
    func cycleAfterNodeLimit() {
        var sketch = Sketch()
        sketch.edge("Screen", "a", "A")
        sketch.edge("Screen", "b", "B")
        sketch.edge("Screen", "c", "C")
        sketch.edge("B", "screen", "Screen")
        #expect(cycle(sketch.search(limits: .init(maxNodes: 3))) == "Screen.b → B.screen → Screen")
    }

    @Test("Objects of a pruned module are dead ends; the same graph unpruned has the cycle")
    func pruneByModule() {
        var sketch = Sketch()
        sketch.node("Button", module: "UIKitCore")
        sketch.edge("Screen", "button", "Button")
        sketch.edge("Button", "action", "Screen")
        #expect(sketch.search(pruning: ["UIKitCore"]).outcome == .notFound)
        #expect(cycle(sketch.search()) == "Screen.button → Button.action → Screen")
    }

    @Test("The start object is expanded even in a pruned module; closures have no module and are never pruned")
    func pruneSparesStartAndClosures() {
        var sketch = Sketch()
        sketch.node("Screen", module: "UIKitCore")
        sketch.closure("closure #1 in Screen.viewDidLoad()")
        sketch.edge("Screen", "handler", "closure #1 in Screen.viewDidLoad()")
        sketch.edge("closure #1 in Screen.viewDidLoad()", RetainPath([.capture(0)]), "Screen")
        #expect(cycle(sketch.search(pruning: ["UIKitCore"]))
                == "Screen.handler → closure #1 in Screen.viewDidLoad().capture 0 → Screen")
    }

    @Test("Paths read the way the code is written")
    func pathDescriptions() {
        #expect(RetainPath([.field("items"), .element(2), .field("onTap")]).description == "items[2].onTap")
        #expect(RetainPath([.field("handlers"), .value(key: "\"save\"")]).description == #"handlers["save"]"#)
        #expect(RetainPath([.field("onRefresh"), .closure(function: "closure #1 in viewDidLoad()")]).description
                == "onRefresh {closure #1 in viewDidLoad()}")
        #expect(RetainPath([.capture(1)]).description == "capture 1")
        #expect(RetainPath([.associatedObject(key: "helperKey")]).description == "associated helperKey")
        #expect(RetainPath([.unverified]).description == "?")
    }
}

@Suite("Confidence, time budget, export")
struct RetainGraphExtrasTests {
    @Test("A cycle is certain only if every reference in it is")
    func certainty() throws {
        var sketch = Sketch()
        sketch.edge("Screen", "block", "Block")
        sketch.edge("Block", "capture", "Screen", certain: false)
        guard case .found(let found) = sketch.search().outcome else { Issue.record("no cycle"); return }
        #expect(found.certainties == [true, false])
        #expect(!found.isCertain)

        var strong = Sketch()
        strong.edge("Screen", "model", "Model")
        strong.edge("Model", "owner", "Screen")
        #expect(strong.search().cycle?.isCertain == true)
    }

    @Test("Equally short cycles: one through the start's own module is found before one through a framework")
    func prefersStartModule() {
        var sketch = Sketch()
        sketch.node("Button", module: "UIKitCore")
        sketch.edge("Screen", "button", "Button")
        sketch.edge("Screen", "model", "Model")
        sketch.edge("Button", "target", "Screen")
        sketch.edge("Model", "owner", "Screen")
        #expect(cycle(sketch.search()) == "Screen.model → Model.owner → Screen")
    }

    @Test("Run a slice at a time, the search ends with the same result as all at once")
    func slices() {
        var sketch = Sketch()
        sketch.edge("Screen", "a", "A")
        sketch.edge("A", "b", "B")
        sketch.edge("B", "c", "C")
        sketch.edge("C", "screen", "Screen")
        let searcher = RetainCycleSearcher(source: sketch.graph, start: sketch.node("Screen"), limits: .init(), prunedModules: [])
        var steps = 0
        var result: RetainCycleSearch?
        while result == nil {
            steps += 1
            result = searcher.advance(for: 0)
        }
        #expect(steps == 4)
        #expect(result?.outcome == sketch.search().outcome)
    }

    @Test("A time budget already spent stops the search as inconclusive")
    func timeBudget() {
        var sketch = Sketch()
        for index in 0..<50 { sketch.edge("Screen", "item\(index)", "Item\(index)") }
        let search = sketch.search(limits: .init(maxDuration: 0))
        #expect(search.outcome == .inconclusive(.time))
        #expect(search.duration >= 0)
    }

    @Test("DOT: every node and reference, the cycle in red, uncertain references dashed")
    func dotExport() throws {
        var sketch = Sketch()
        sketch.node("Screen")
        sketch.closure("closure #1")
        sketch.edge("Screen", "handler", "closure #1")
        sketch.edge("closure #1", RetainPath([.unverified]), "Screen", certain: false)
        sketch.edge("Screen", "label", "Label")
        let search = sketch.search()
        let dot = search.explored.dot(highlighting: search.cycle)
        #expect(dot.hasPrefix("digraph RetainGraph {"))
        #expect(dot.contains(#"n1 [label="Screen\nApp", color=red, penwidth=2];"#))
        #expect(dot.contains(#"n2 [label="closure #1", color=red, penwidth=2];"#))
        #expect(dot.contains(#"n1 -> n2 [label="handler", color=red, fontcolor=red, penwidth=2];"#))
        #expect(dot.contains(#"n2 -> n1 [label="?", style=dashed, color=red, fontcolor=red, penwidth=2];"#))
        #expect(dot.contains(#"n1 -> n3 [label="label"];"#))
    }

    @Test("JSON: nodes with their kind, edges with their path and certainty, and the cycle as ids")
    func jsonExport() throws {
        var sketch = Sketch()
        sketch.edge("Screen", "model", "Model")
        sketch.closure("closure #1")
        sketch.edge("Model", "onChange", "closure #1")
        sketch.edge("closure #1", RetainPath([.capture(0)]), "Screen", certain: false)
        let search = sketch.search()
        let object = try #require(try JSONSerialization.jsonObject(with: search.explored.json(highlighting: search.cycle)) as? [String: Any])
        let nodes = try #require(object["nodes"] as? [[String: Any]])
        #expect(nodes.map { $0["name"] as? String } == ["Screen", "Model", "closure #1"])
        #expect(nodes.map { $0["kind"] as? String } == ["object", "object", "closure"])
        let edges = try #require(object["edges"] as? [[String: Any]])
        #expect(edges.map { $0["path"] as? String } == ["model", "onChange", "capture 0"])
        #expect(edges.map { $0["certain"] as? Bool } == [true, true, false])
        #expect(object["cycle"] as? [String] == ["0x1", "0x2", "0x3"])
    }
}

@Suite("What holds an object")
struct RetainChainSearchTests {
    @Test("From several roots, the shortest chain to the object wins, whichever root it starts from")
    func shortestFromAnyRoot() {
        var sketch = Sketch()
        sketch.closure("Task")
        sketch.edge("Task", "operation", "Model")
        sketch.edge("Model", "owner", "Screen")
        sketch.edge("Timer", "target", "Screen")
        let search = sketch.holders(of: "Screen", from: ["Task", "Timer"])
        #expect(cycle(search) == "Timer.target → Screen")
        guard case .found(let chain) = search.outcome else { return }
        #expect(!chain.isCycle)
        #expect(chain.end.name == "Screen")
    }

    @Test("A root that is the object itself is a chain of no references")
    func rootIsTheObject() {
        var sketch = Sketch()
        sketch.edge("Observer", "block", "Screen")
        let search = sketch.holders(of: "Observer", from: ["Observer"])
        guard case .found(let chain) = search.outcome else { Issue.record("not found"); return }
        #expect(chain.nodes.isEmpty)
        #expect(chain.description == "Observer")
    }

    @Test("Nothing reaches it: not found")
    func unreachable() {
        var sketch = Sketch()
        sketch.edge("Timer", "target", "Other")
        sketch.node("Screen")
        #expect(sketch.holders(of: "Screen", from: ["Timer"]).outcome == .notFound)
    }

    @Test("JSON names a chain root to end")
    func chainExport() throws {
        var sketch = Sketch()
        sketch.edge("Timer", "target", "Screen")
        let search = sketch.holders(of: "Screen", from: ["Timer"])
        let object = try #require(try JSONSerialization.jsonObject(with: search.explored.json(highlighting: search.cycle)) as? [String: Any])
        #expect(object["chain"] as? [String] == ["0x1", "0x2"])
        #expect(object["cycle"] == nil)
    }
}

// MARK: - Live objects

private final class Screen { var worker: Worker? }
private final class Worker { var delegate: Screen? }
private final class Box<Value> {}

/// Test-only source: Mirror cannot tell weak from strong (ADR 002), so only strong fields are used here.
private struct MirrorSource: RetainGraphSource {
    func node(for object: AnyObject) -> RetainGraph.Node {
        RetainGraph.Node(id: UInt(bitPattern: ObjectIdentifier(object)),
                         kind: .object(type: String(describing: type(of: object)), module: moduleName(of: type(of: object))))
    }

    func strongReferences(from object: AnyObject) -> [RetainReference<AnyObject>] {
        Mirror(reflecting: object).children.compactMap { child in
            guard let label = child.label, let value = Mirror(reflecting: child.value).children.first?.value,
                  type(of: value) is AnyClass else { return nil }
            return RetainReference(RetainPath([.field(label)]), value as AnyObject)
        }
    }
}

@Suite("Live objects")
struct LiveObjectTests {
    @Test("Screen → worker → delegate → Screen, read from real objects")
    func strongDelegateCycle() {
        let screen = Screen(), worker = Worker()
        screen.worker = worker
        worker.delegate = screen
        defer { worker.delegate = nil }

        let search = MirrorSource().shortestCycle(through: screen)
        #expect(cycle(search) == "Screen.worker → Worker.delegate → Screen")
        guard case .found(let found) = search.outcome else { return }
        #expect(found.nodes.map(\.id) == [ObjectIdentifier(screen), ObjectIdentifier(worker)].map { UInt(bitPattern: $0) })
        #expect(found.nodes.allSatisfy { $0.module == "LeakGraphTests" })
    }

    @Test("Module names: Swift module for Swift classes, generics included; the image for Objective-C classes")
    func moduleNames() {
        #expect(moduleName(of: Screen.self) == "LeakGraphTests")
        #expect(moduleName(of: Box<Int>.self) == "LeakGraphTests")
        #expect(moduleName(of: NSObject.self) == "libobjc.A")
    }
}

#endif
