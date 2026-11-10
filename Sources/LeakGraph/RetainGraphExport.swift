//
//  RetainGraphExport.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

extension RetainGraph {
    /// Graphviz source: `dot -Tsvg graph.dot -o graph.svg`. The chain is red, uncertain references dashed.
    package func dot(highlighting chain: RetainChain? = nil) -> String {
        let cycleNodes = Set((chain?.nodes ?? []).map(\.id) + (chain.map { [$0.end.id] } ?? []))
        let cycleEdges = Set(chain.map { chain in
            chain.nodes.indices.map { "\(chain.nodes[$0].id)>\(chain.target(of: $0).id)>\(chain.paths[$0])" }
        } ?? [])

        var lines = ["digraph RetainGraph {", "  node [shape=box, fontname=Menlo, fontsize=10];",
                     "  edge [fontname=Menlo, fontsize=9];"]
        for node in nodes.values.sorted(by: { $0.id < $1.id }) {
            let label = Self.escaped(node.name) + (node.module.map { "\\n" + Self.escaped($0) } ?? "")
            let style = cycleNodes.contains(node.id) ? ", color=red, penwidth=2" : ""
            lines.append("  n\(node.id) [label=\"\(label)\"\(style)];")
        }
        for id in nodes.keys.sorted() {
            for edge in edges(from: id) {
                var attributes = ["label=\"\(Self.escaped(edge.path.description))\""]
                if !edge.isCertain { attributes.append("style=dashed") }
                if cycleEdges.contains("\(edge.from)>\(edge.to)>\(edge.path)") {
                    attributes.append("color=red, fontcolor=red, penwidth=2")
                }
                lines.append("  n\(edge.from) -> n\(edge.to) [\(attributes.joined(separator: ", "))];")
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `{"nodes": [...], "edges": [...], "cycle": [ids]}`, ids as hex addresses, `kind` one of
    /// `object`, `closure`, `block`, `box`, `task`. A chain that is not a cycle is `"chain"`, root to end.
    package func json(highlighting chain: RetainChain? = nil) -> Data {
        func hex(_ id: Node.ID) -> String { "0x" + String(id, radix: 16) }
        let nodeList: [[String: Any]] = nodes.values.sorted { $0.id < $1.id }.map { node in
            var entry: [String: Any] = ["id": hex(node.id), "name": node.name]
            switch node.kind {
            case .object(_, let module):
                entry["kind"] = "object"
                if let module { entry["module"] = module }
            case .closure: entry["kind"] = "closure"
            case .block: entry["kind"] = "block"
            case .box: entry["kind"] = "box"
            case .task(let function):
                entry["kind"] = "task"
                entry["function"] = function
            }
            return entry
        }
        let edgeList: [[String: Any]] = nodes.keys.sorted().flatMap { id in
            edges(from: id).map {
                ["from": hex($0.from), "to": hex($0.to), "path": $0.path.description, "certain": $0.isCertain]
            }
        }
        var root: [String: Any] = ["nodes": nodeList, "edges": edgeList]
        if let chain {
            if chain.isCycle {
                root["cycle"] = chain.nodes.map { hex($0.id) }
            } else {
                root["chain"] = (chain.nodes + [chain.end]).map { hex($0.id) }
            }
        }
        // Only strings, numbers, booleans, arrays and dictionaries: serialization cannot fail.
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

#endif
