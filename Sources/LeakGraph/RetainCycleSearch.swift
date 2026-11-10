//
//  RetainCycleSearch.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Dispatch

/// Strong references from one object to another: a cycle when it ends where it started, otherwise
/// what holds an object, from a root such as a running task.
package struct RetainChain: Sendable, Equatable, CustomStringConvertible {
    /// Starts with the object the search started from.
    package let nodes: [RetainGraph.Node]
    /// `paths[i]` is where `nodes[i]` holds the next node: `nodes[i + 1]`, or `end` for the last one.
    package let paths: [RetainPath]
    /// One per path.
    package let certainties: [Bool]
    /// The object held. `nodes[0]` for a cycle. With no nodes, a root that is the object itself.
    package let end: RetainGraph.Node

    package init(nodes: [RetainGraph.Node], paths: [RetainPath], certainties: [Bool], end: RetainGraph.Node? = nil) {
        precondition(nodes.count == paths.count && paths.count == certainties.count, "one path and certainty per node")
        guard let end = end ?? nodes.first else { preconditionFailure("a chain needs an end") }
        self.nodes = nodes
        self.paths = paths
        self.certainties = certainties
        self.end = end
    }

    package var length: Int { nodes.count }

    package var isCycle: Bool { nodes.first?.id == end.id }

    /// Every reference is known to be strong. Otherwise some may be weak and the chain may not exist.
    package var isCertain: Bool { certainties.allSatisfy { $0 } }

    /// The node `paths[index]` points to.
    package func target(of index: Int) -> RetainGraph.Node {
        index + 1 < nodes.count ? nodes[index + 1] : end
    }

    /// `ProfileVC.viewModel → ProfileViewModel.onChange → ProfileVC`. Has no address: the same shape every run.
    package var description: String {
        (zip(nodes, paths).map { $1.steps.isEmpty ? $0.name : "\($0.name).\($1)" } + [end.name]).joined(separator: " → ")
    }
}

package struct RetainCycleSearch: Sendable {
    package struct Limits: Sendable {
        /// The longest cycle looked for.
        package var maxDepth: Int
        /// The most objects visited, the start included.
        package var maxNodes: Int
        /// Total time spent searching, all slices together. `nil`: none.
        package var maxDuration: Double?

        package init(maxDepth: Int = 10, maxNodes: Int = 1_000, maxDuration: Double? = nil) {
            precondition(maxDepth >= 1 && maxNodes >= 1, "limits must be at least 1")
            self.maxDepth = maxDepth
            self.maxNodes = maxNodes
            self.maxDuration = maxDuration
        }
    }

    package enum Limit: String, Sendable, Equatable {
        case depth
        case nodes
        case time
    }

    package enum Outcome: Sendable, Equatable {
        /// The shortest cycle through the start, or chain to a goal. After the node limit is hit it may not be the shortest.
        case found(RetainChain)
        /// Every object reachable within the limits was visited, pruned modules aside: no cycle through the start.
        case notFound
        /// No cycle before a limit stopped the search: there may be one further away.
        case inconclusive(Limit)
    }

    package let outcome: Outcome
    /// Every object and reference visited, for debugging and reports.
    package let explored: RetainGraph
    /// Objects only partly read: a cycle through one of them may have been missed.
    package let partlyRead: Int
    /// Time spent searching, slices added up.
    package let duration: Double

    package var cycle: RetainChain? {
        if case .found(let cycle) = outcome { return cycle }
        return nil
    }
}

/// Breadth-first from the start, so the first reference back to it closes a shortest cycle. Runs a slice
/// at a time, so a search on the main thread never holds a frame for long.
///
/// With several starts and a set of goals, finds the shortest chain from any start to any goal instead:
/// which root (a task, a timer…) holds an object.
///
/// Within one depth, objects from the start's module and closures go first: a cycle through the app's
/// own code is found before the search wanders into framework internals. It is still a shortest one.
package final class RetainCycleSearcher<Source: RetainGraphSource> {
    private typealias Item = (object: Source.Object, node: RetainGraph.Node)

    private let source: Source
    private let limits: RetainCycleSearch.Limits
    private let prunedModules: Set<String>
    private let start: RetainGraph.Node
    private let startIDs: Set<RetainGraph.Node.ID>
    /// `nil`: back to the start.
    private let goals: Set<RetainGraph.Node.ID>?
    private var explored = RetainGraph()
    private var reachedBy: [RetainGraph.Node.ID: RetainGraph.Edge] = [:]
    // Holding the objects here keeps live ones alive for the whole search.
    private var level: [Item]
    private var nextLevel: [Item] = []
    private var index = 0
    private var depth = 0
    private var limitHit: RetainCycleSearch.Limit?
    private var partlyRead = 0
    private var spent: Double = 0
    private(set) var result: RetainCycleSearch?

    package convenience init(source: Source, start: Source.Object, limits: RetainCycleSearch.Limits, prunedModules: Set<String>) {
        self.init(source: source, starts: [start], goals: nil, limits: limits, prunedModules: prunedModules)
    }

    /// `goals: nil` looks for a cycle through the only start.
    package init(source: Source, starts: [Source.Object], goals: Set<RetainGraph.Node.ID>?, limits: RetainCycleSearch.Limits,
                 prunedModules: Set<String>) {
        precondition(!starts.isEmpty && (goals != nil || starts.count == 1), "a cycle search has exactly one start")
        self.source = source
        self.limits = limits
        self.prunedModules = prunedModules
        self.goals = goals
        level = []
        for object in starts {
            let node = source.node(for: object)
            guard explored.nodes[node.id] == nil else { continue }
            explored.add(node)
            level.append((object, node))
        }
        start = level[0].node
        startIDs = Set(level.map(\.node.id))
        if let root = level.first(where: { goals?.contains($0.node.id) == true }) {
            result = RetainCycleSearch(outcome: .found(RetainChain(nodes: [], paths: [], certainties: [], end: root.node)),
                                       explored: explored, partlyRead: 0, duration: 0)
        }
    }

    /// Searches for about `slice` seconds, at least one object. Returns the result once finished.
    package func advance(for slice: Double) -> RetainCycleSearch? {
        if let result { return result }
        let began = DispatchTime.now().uptimeNanoseconds
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9 }
        defer { spent += elapsed() }

        var expanded = 0
        while true {
            if expanded > 0, elapsed() >= slice { return nil }
            if let budget = limits.maxDuration, spent + elapsed() > budget { return finish(.inconclusive(.time), elapsed()) }
            guard let item = nextItem() else { return finish(limitHit.map { .inconclusive($0) } ?? .notFound, elapsed()) }
            expanded += 1
            if let cycle = expand(item) { return finish(.found(cycle), elapsed()) }
        }
    }

    private func nextItem() -> Item? {
        if index == level.count {
            guard !nextLevel.isEmpty else { return nil }
            let preferred = nextLevel.filter(isPreferred)
            level = preferred + nextLevel.filter { !isPreferred($0) }
            nextLevel = []
            index = 0
            depth += 1
        }
        defer { index += 1 }
        return level[index]
    }

    private func isPreferred(_ item: Item) -> Bool {
        item.node.module == nil || item.node.module == start.module
    }

    private func expand(_ item: Item) -> RetainChain? {
        if !startIDs.contains(item.node.id), let module = item.node.module, prunedModules.contains(module) { return nil }
        guard depth < limits.maxDepth else {
            limitHit = limitHit ?? .depth
            return nil
        }
        let references = source.strongReferences(from: item.object)
        if !source.readCompletely(item.object) { partlyRead += 1 }
        for reference in references {
            let target = source.node(for: reference.target)
            let edge = RetainGraph.Edge(from: item.node.id, to: target.id, path: reference.path, isCertain: reference.isCertain)
            if goals?.contains(target.id) ?? (target.id == start.id) {
                explored.add(target)
                explored.addEdge(from: edge.from, to: edge.to, path: edge.path, isCertain: edge.isCertain)
                return chain(endedBy: edge, at: target)
            }
            if explored.nodes[target.id] == nil {
                // Keep scanning what is already queued: a reference back to the start can still turn up.
                guard explored.nodes.count < limits.maxNodes else {
                    limitHit = .nodes
                    continue
                }
                explored.add(target)
                reachedBy[target.id] = edge
                nextLevel.append((reference.target, target))
            }
            explored.addEdge(from: edge.from, to: edge.to, path: edge.path, isCertain: edge.isCertain)
        }
        return nil
    }

    private func finish(_ outcome: RetainCycleSearch.Outcome, _ elapsed: Double) -> RetainCycleSearch {
        let result = RetainCycleSearch(outcome: outcome, explored: explored, partlyRead: partlyRead, duration: spent + elapsed)
        self.result = result
        level = []
        nextLevel = []
        return result
    }

    private func chain(endedBy last: RetainGraph.Edge, at end: RetainGraph.Node) -> RetainChain {
        var edges = [last]
        while let step = reachedBy[edges[edges.count - 1].from] {
            edges.append(step)
        }
        edges.reverse()
        return RetainChain(nodes: edges.map { explored.node(for: $0.from) },
                           paths: edges.map(\.path),
                           certainties: edges.map(\.isCertain),
                           end: end)
    }
}

extension RetainGraphSource {
    /// The whole search at once. Objects in `prunedModules` are visited but their references are not followed.
    package func shortestCycle(
        through start: Object,
        limits: RetainCycleSearch.Limits = .init(),
        prunedModules: Set<String> = []
    ) -> RetainCycleSearch {
        let searcher = RetainCycleSearcher(source: self, start: start, limits: limits, prunedModules: prunedModules)
        while true {
            if let result = searcher.advance(for: .infinity) { return result }
        }
    }

    /// The whole search at once: the shortest chain from any of `roots` to any of `goals`.
    package func shortestChain(
        from roots: [Object],
        to goals: Set<RetainGraph.Node.ID>,
        limits: RetainCycleSearch.Limits = .init(),
        prunedModules: Set<String> = []
    ) -> RetainCycleSearch {
        let searcher = RetainCycleSearcher(source: self, starts: roots, goals: goals, limits: limits, prunedModules: prunedModules)
        while true {
            if let result = searcher.advance(for: .infinity) { return result }
        }
    }
}

#endif
