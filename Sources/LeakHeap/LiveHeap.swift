//
//  LiveHeap.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

/// Strong references of live objects: Swift stored properties (ownership from field metadata, ADR 002),
/// closure captures, Objective-C ivars (ARC ivar layout), collections, blocks and associated objects.
///
/// One instance per search: it remembers every object it has described, so memory whose layout is
/// unknown can be matched against them by address without dereferencing anything.
package final class LiveHeap: RetainGraphSource {
    package enum Object {
        case object(AnyObject)
        /// A closure context or a captured-var box. `keepAlive` is the closure value holding it.
        case context(UnsafeRawPointer, kind: RetainGraph.Node.Kind, keepAlive: Any)
        /// A running task, by address: it holds its operation closure until the operation returns.
        /// `keepAlive` keeps the operation's context alive.
        case task(UInt, operation: TaskOperation, keepAlive: Any)
    }

    /// The closure a task runs, read when the task was created.
    package struct TaskOperation: Sendable {
        package let name: String
        package let function: UInt
        package let context: UInt
    }

    private var seen: [UInt: Object] = [:]
    private var partlyRead: Set<UInt> = []
    private let extraReferences: (AnyObject) -> [(path: RetainPath, target: AnyObject)]

    /// `extraReferences`: strong references a framework keeps outside anything readable, e.g. a view's
    /// subviews, held through Core Animation's own storage.
    package init(extraReferences: @escaping (AnyObject) -> [(path: RetainPath, target: AnyObject)] = { _ in [] }) {
        self.extraReferences = extraReferences
    }

    package func node(for object: Object) -> RetainGraph.Node {
        switch object {
        case .object(let instance):
            let id = UInt(bitPattern: ObjectIdentifier(instance))
            if seen[id] == nil { seen[id] = object }
            return RetainGraph.Node(id: id, kind: NodeKinds.shared.kind(of: type(of: instance)))
        case .context(let pointer, let kind, _):
            let id = UInt(bitPattern: pointer)
            if seen[id] == nil { seen[id] = object }
            return RetainGraph.Node(id: id, kind: kind)
        case .task(let address, let operation, _):
            return RetainGraph.Node(id: address, kind: .task(function: operation.name))
        }
    }

    package func strongReferences(from object: Object) -> [RetainReference<Object>] {
        var collector = ReferenceCollector(known: { [unowned self] in self.seen[$0] })
        switch object {
        case .object(let instance):
            references(of: instance, into: &collector)
        case .context(let pointer, let kind, let keepAlive):
            collect(context: pointer, kind: kind, keepAlive: keepAlive, into: &collector)
        case .task(_, let operation, let keepAlive):
            collector.closure(function: operation.function, context: operation.context, at: RetainPath([.field("operation")]),
                              certain: true, keepAlive: keepAlive)
        }
        if collector.isPartial { partlyRead.insert(node(for: object).id) }
        return collector.references
    }

    private func collect(context pointer: UnsafeRawPointer, kind: RetainGraph.Node.Kind, keepAlive: Any,
                         into collector: inout ReferenceCollector) {
        switch kind {
        case .box:
            collector.captures(ofContext: pointer, isBox: true, keepAlive: keepAlive)
        default:
            collector.captures(ofContext: pointer, isBox: false, keepAlive: keepAlive)
        }
    }

    /// The closure a task runs, from the context `swift_task_create` receives: the generic wrapper Task.init
    /// builds around the operation. That wrapper is released as soon as the task starts; the operation lives on
    /// in the task's frame. `nil` if it cannot be read.
    package static func taskOperation(ofContext context: UnsafeRawPointer) -> TaskOperation? {
        var collector = ReferenceCollector(known: { _ in nil })
        collector.captures(ofContext: context, isBox: false, keepAlive: ())
        guard let closure = collector.firstClosure, closure.context != 0 else { return nil }
        return TaskOperation(name: SymbolNames.closure(at: closure.function), function: closure.function, context: closure.context)
    }

    /// Objects `object` points to within `depth` steps, weak references included: who a task works for.
    /// Weak targets are not followed further.
    package func pointees(of object: Object, depth: Int) -> [AnyObject] {
        var found: [ObjectIdentifier: AnyObject] = [:]
        var level = [object]
        for _ in 0..<depth {
            var next: [Object] = []
            for current in level {
                var collector = ReferenceCollector(known: { [unowned self] in self.seen[$0] })
                collector.collectsWeak = true
                switch current {
                case .object(let instance): references(of: instance, into: &collector)
                case .context(let pointer, let kind, let keepAlive): collect(context: pointer, kind: kind, keepAlive: keepAlive, into: &collector)
                case .task(_, let operation, let keepAlive):
                    collector.closure(function: operation.function, context: operation.context, at: RetainPath([.field("operation")]),
                                      certain: true, keepAlive: keepAlive)
                }
                for reference in collector.references {
                    if case .object(let target) = reference.target {
                        guard found.updateValue(target, forKey: ObjectIdentifier(target)) == nil else { continue }
                    }
                    next.append(reference.target)
                }
                for (_, target) in collector.weakReferences {
                    found[ObjectIdentifier(target)] = target
                }
            }
            level = next
        }
        return Array(found.values)
    }

    package func readCompletely(_ object: Object) -> Bool {
        !partlyRead.contains(node(for: object).id)
    }

    private func references(of object: AnyObject, into collector: inout ReferenceCollector) {
        let cls: AnyClass = type(of: object)
        if ObjCReferences.isBlock(cls) {
            ObjCReferences.blockReferences(of: object, into: &collector)
            return
        }
        if ObjCReferences.collectionReferences(of: object, into: &collector) { return }

        let stored = SwiftMetadata.isSwiftClass(cls) ? SwiftMetadata.storedFields(ofClass: cls) : nil
        if let stored {
            swiftFields(of: object, stored, into: &collector)
        }
        var current: AnyClass? = cls
        while let level = current, level !== NSObject.self {
            if SwiftMetadata.isSwiftClass(level) {
                if stored == nil { unverifiedFields(of: object, declaredBy: level, into: &collector) }
            } else {
                for (name, ivar) in ObjCReferences.strongIvars(of: level) {
                    if let value = object_getIvar(object, ivar) {
                        collector.add(RetainPath([.field(name)]), .object(value as AnyObject))
                    }
                }
            }
            current = class_getSuperclass(level)
        }
        for (path, target) in extraReferences(object) {
            collector.add(path, .object(target))
        }
        for (key, value) in AssociatedObjects.strongValues(of: object) {
            collector.add(RetainPath([.associatedObject(key: key)]), .object(value))
        }
    }

    /// Strong fields only, loaded at the offsets the runtime reports: reading an `unowned` field whose object
    /// is gone traps, and an `unowned(unsafe)` one may dangle. Weak ones are loaded only when asked for.
    private func swiftFields(of object: AnyObject, _ fields: [SwiftMetadata.StoredField], into collector: inout ReferenceCollector) {
        let base = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
        for field in fields {
            switch field.ownership {
            case .strong:
                collector.walk(loadValue(of: field.type, at: base + field.offset), at: RetainPath([.field(Self.displayName(field.name))]))
            case .weak:
                collector.weakField(at: base + field.offset, path: RetainPath([.field(Self.displayName(field.name))]))
            case .unowned, .unownedUnsafe:
                break
            }
        }
    }

    /// No reflection metadata: the ivar list still has names and offsets but no
    /// ownership, so each field's word is only matched against objects already in the graph.
    private func unverifiedFields(of object: AnyObject, declaredBy cls: AnyClass, into collector: inout ReferenceCollector) {
        collector.markPartial()
        var count: UInt32 = 0
        guard let list = class_copyIvarList(cls, &count) else { return }
        defer { free(list) }
        let base = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
        for index in 0..<Int(count) {
            let ivar = list[index]
            let address = base.load(fromByteOffset: ivar_getOffset(ivar), as: UInt.self)
            if let target = collector.known(address) {
                let name = ivar_getName(ivar).map { String(cString: $0) } ?? "?"
                collector.add(RetainPath([.field(Self.displayName(name))]), target, certain: false)
            }
        }
    }

    /// Per class, computed once per process: naming classes is the costly part of a cold search.
    private final class NodeKinds: @unchecked Sendable {
        static let shared = NodeKinds()
        private let lock = NSLock()
        private var kinds: [ObjectIdentifier: RetainGraph.Node.Kind] = [:]

        func kind(of cls: AnyClass) -> RetainGraph.Node.Kind {
            lock.lock()
            if let kind = kinds[ObjectIdentifier(cls)] { lock.unlock(); return kind }
            lock.unlock()
            let kind: RetainGraph.Node.Kind
            if ObjCReferences.isBlock(cls) {
                kind = .block
            } else if SwiftMetadata.isSwiftClass(cls), let swift = SwiftMetadata.name(ofSwiftClass: cls) {
                kind = .object(type: swift.name, module: swift.module)
            } else {
                kind = .object(type: Self.name(of: cls), module: moduleName(of: cls))
            }
            lock.lock()
            kinds[ObjectIdentifier(cls)] = kind
            lock.unlock()
            return kind
        }

        /// The Objective-C runtime's name for Objective-C classes: naming them through Swift costs ~0.6 ms each.
        private static func name(of cls: AnyClass) -> String {
            SwiftMetadata.isSwiftClass(cls) ? String(describing: cls) : String(cString: class_getName(cls))
        }
    }

    /// Pays the one-time costs of a first search (image table, class names, ivar layouts, metadata
    /// lookups) ahead of time. Safe off the main thread: everything it fills is behind a lock.
    package static func warmUp(classes: [AnyClass]) {
        for cls in classes {
            var current: AnyClass? = cls
            while let level = current {
                _ = NodeKinds.shared.kind(of: level)
                if SwiftMetadata.isSwiftClass(level) { _ = SwiftMetadata.fields(ofClass: level) } else { _ = ObjCReferences.strongIvars(of: level) }
                current = class_getSuperclass(level)
            }
        }
        let sample = WarmUpSample()
        sample.handler = { [sample] in _ = sample.items }
        _ = LiveHeap().shortestCycle(through: .object(sample))
        sample.handler = nil
    }

    private final class WarmUpSample {
        var handler: (() -> Void)?
        var items: [AnyObject] = [NSObject(), NSMutableArray(), NSMutableDictionary()]
    }

    /// `$__lazy_storage_$_foo` → `foo`.
    private static func displayName(_ field: String) -> String {
        let lazyPrefix = "$__lazy_storage_$_"
        return field.hasPrefix(lazyPrefix) ? String(field.dropFirst(lazyPrefix.count)) : field
    }
}

#endif
