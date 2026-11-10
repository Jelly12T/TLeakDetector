//
//  RetainGraph.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED

/// Objects and the strong references between them. Weak and unowned references are not edges.
package struct RetainGraph: Sendable {
    package struct Node: Hashable, Sendable {
        /// The address for live objects.
        package typealias ID = UInt

        package enum Kind: Hashable, Sendable {
            /// A class instance, Swift or Objective-C. `module` is what prune matches; `nil` when unknown.
            case object(type: String, module: String?)
            /// The heap context of a Swift closure: holds what the closure captured.
            case closure(function: String)
            /// An Objective-C block and what it captured.
            case block
            /// The heap box of a `var` captured by a closure.
            case box(type: String)
            /// A running Swift task: holds its operation closure until the operation returns.
            case task(function: String)
        }

        package let id: ID
        package let kind: Kind

        package init(id: ID, kind: Kind) {
            self.id = id
            self.kind = kind
        }

        /// Only objects have a module; the rest is never pruned.
        package var module: String? {
            if case .object(_, let module) = kind { return module }
            return nil
        }

        package var name: String {
            switch kind {
            case .object(let type, _): type
            case .closure(let function): function
            case .block: "block"
            case .box(let type): "var \(type)"
            case .task: "Task"
            }
        }
    }

    package struct Edge: Hashable, Sendable {
        package let from: Node.ID
        package let to: Node.ID
        package let path: RetainPath
        /// `false` when found without knowing its ownership, e.g. by matching addresses in memory
        /// whose layout is unknown. It may be weak or unowned.
        package let isCertain: Bool
    }

    package private(set) var nodes: [Node.ID: Node] = [:]
    private var outgoing: [Node.ID: [Edge]] = [:]

    package init() {}

    package var edgeCount: Int { outgoing.values.reduce(0) { $0 + $1.count } }

    package mutating func add(_ node: Node) {
        if nodes[node.id] == nil { nodes[node.id] = node }
    }

    package mutating func addEdge(from: Node.ID, to: Node.ID, path: RetainPath, isCertain: Bool = true) {
        precondition(nodes[from] != nil && nodes[to] != nil, "add both nodes before the edge")
        outgoing[from, default: []].append(Edge(from: from, to: to, path: path, isCertain: isCertain))
    }

    /// In the order they were added.
    package func edges(from id: Node.ID) -> [Edge] {
        outgoing[id] ?? []
    }
}

/// Where a reference sits inside the object holding it, outermost step first: `items[2].onTap`.
package struct RetainPath: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    package enum Step: Hashable, Sendable {
        /// A stored property or an ivar: `delegate`, `_view`.
        case field(String)
        /// An element of an array, a set or a hash table.
        case element(Int)
        /// A dictionary or map table key.
        case key(Int)
        /// A dictionary or map table value, by its key.
        case value(key: String)
        /// What a closure or a block captured, in capture order.
        case capture(Int)
        /// Through a closure whose context is the target itself: `{ self.refresh() }` captures only `self`.
        case closure(function: String)
        /// Set with `objc_setAssociatedObject`.
        case associatedObject(key: String)
        /// The address was found in memory whose layout is unknown.
        case unverified
    }

    package let steps: [Step]

    package init(_ steps: [Step]) {
        self.steps = steps
    }

    package init(stringLiteral field: String) {
        self.init([.field(field)])
    }

    package func appending(_ step: Step) -> RetainPath {
        RetainPath(steps + [step])
    }

    package var description: String {
        var text = ""
        for step in steps {
            switch step {
            case .field(let name): text += text.isEmpty ? name : ".\(name)"
            case .element(let index): text += "[\(index)]"
            case .key(let index): text += "keys[\(index)]"
            case .value(let key): text += "[\(key)]"
            case .capture(let index): text += text.isEmpty ? "capture \(index)" : ".capture \(index)"
            case .closure(let function): text += text.isEmpty ? "{\(function)}" : " {\(function)}"
            case .associatedObject(let key): text += text.isEmpty ? "associated \(key)" : ".associated \(key)"
            case .unverified: text += text.isEmpty ? "?" : " ?"
            }
        }
        return text
    }
}

/// A reference the source believes is strong. `isCertain` is `false` when it could not be proven.
package struct RetainReference<Object> {
    package let path: RetainPath
    package let target: Object
    package let isCertain: Bool

    package init(_ path: RetainPath, _ target: Object, isCertain: Bool = true) {
        self.path = path
        self.target = target
        self.isCertain = isCertain
    }
}

/// Where cycle search reads strong references: a live heap, or a `RetainGraph` built by hand.
/// Strong or not is a property of the slot holding the reference, so only the source can tell.
package protocol RetainGraphSource {
    associatedtype Object

    func node(for object: Object) -> RetainGraph.Node
    /// Strong references only, in a stable order: it decides which of two equally short cycles is found.
    func strongReferences(from object: Object) -> [RetainReference<Object>]
    /// After `strongReferences(from:)`: `false` when part of the object could not be read precisely, so
    /// a reference from it may have been missed. Then "no cycle" is not proven.
    func readCompletely(_ object: Object) -> Bool
}

extension RetainGraphSource {
    package func readCompletely(_ object: Object) -> Bool { true }
}

extension RetainGraph: RetainGraphSource {
    package func node(for id: Node.ID) -> Node {
        guard let node = nodes[id] else { preconditionFailure("node \(id) is not in the graph") }
        return node
    }

    package func strongReferences(from id: Node.ID) -> [RetainReference<Node.ID>] {
        edges(from: id).map { RetainReference($0.path, $0.to, isCertain: $0.isCertain) }
    }
}

#endif
