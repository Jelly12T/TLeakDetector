//
//  ReferenceCollector.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

/// Collects the strong references held by one object, closure context or box.
struct ReferenceCollector {
    static let maxValueDepth = 6
    static let maxElements = 256
    static let maxScannedBytes = 4_096

    private(set) var references: [RetainReference<LiveHeap.Object>] = []
    /// Set when some memory was only matched by address: a reference to an object not yet seen is missed.
    private(set) var isPartial = false
    /// An object already in the graph at this address, if any. Used only to match addresses, never to dereference.
    let known: (UInt) -> LiveHeap.Object?
    /// Also load weak references, into `weakReferences`. Strong ones are all a retain graph needs; who an
    /// object points to at all (a task's owner) needs both.
    var collectsWeak = false
    private(set) var weakReferences: [(path: RetainPath, target: AnyObject)] = []
    /// The first closure found among captures: what a task wrapper runs.
    private(set) var firstClosure: (function: UInt, context: UInt)?

    init(known: @escaping (UInt) -> LiveHeap.Object?) {
        self.known = known
    }

    mutating func markPartial() {
        isPartial = true
    }

    mutating func add(_ path: RetainPath, _ target: LiveHeap.Object, certain: Bool = true) {
        references.append(RetainReference(path, target, isCertain: certain))
    }

    /// A `weak` stored property: loaded only when weak references are collected.
    mutating func weakField(at slot: UnsafeRawPointer, path: RetainPath) {
        if collectsWeak, let target = WeakReferences.load(at: slot) {
            weakReferences.append((path, target))
        }
    }

    // MARK: - Swift values

    /// A stored value: class instances, closures, and what structs, enums, tuples and collections hold.
    mutating func walk(_ value: Any, at path: RetainPath, certain: Bool = true, depth: Int = 0) {
        guard depth <= Self.maxValueDepth else { return }
        let valueType = type(of: value)
        if valueType is AnyClass {
            add(path, .object(value as AnyObject), certain: certain)
            return
        }
        let metadata = unsafeBitCast(valueType, to: UnsafeRawPointer.self)
        switch SwiftMetadata.kind(of: metadata) {
        case .function:
            closure(value, metadata: metadata, at: path, certain: certain)
        case .struct, .enum, .optional, .tuple:
            children(of: value, type: valueType, at: path, certain: certain, depth: depth)
        default:
            break
        }
    }

    private mutating func children(of value: Any, type valueType: Any.Type, at path: RetainPath, certain: Bool, depth: Int) {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children
        switch mirror.displayStyle {
        case .optional:
            if let wrapped = children.first {
                walk(wrapped.value, at: path, certain: certain, depth: depth + 1)
            }
        case .collection, .set:
            for (index, element) in children.prefix(Self.maxElements).enumerated() {
                walk(element.value, at: path.appending(.element(index)), certain: certain, depth: depth + 1)
            }
        case .dictionary:
            for (index, entry) in children.prefix(Self.maxElements).enumerated() {
                let pair = Array(Mirror(reflecting: entry.value).children)
                guard pair.count == 2 else { continue }
                walk(pair[0].value, at: path.appending(.key(index)), certain: certain, depth: depth + 1)
                walk(pair[1].value, at: path.appending(.value(key: Self.keyDescription(pair[0].value, index: index))),
                     certain: certain, depth: depth + 1)
            }
        case .struct where !(value is CustomReflectable):
            // Property wrappers hide `weak` in a struct field: field metadata tells which ones to skip.
            guard let fields = SwiftMetadata.fields(ofStruct: valueType), fields.count == children.count else {
                isPartial = true
                return
            }
            for (field, index) in zip(fields, children.indices) where field.ownership == .strong {
                walk(children[index].value, at: path.appending(.field(field.name)), certain: certain, depth: depth + 1)
            }
        case .tuple, .enum, .struct:
            // A custom mirror shows what its author chose, not necessarily what is stored, nor how.
            let verified = mirror.displayStyle != .struct
            if !verified { isPartial = true }
            for (index, child) in children.enumerated() {
                // Tuple elements are labelled `.0`, `.1` when unnamed.
                let label = child.label.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 } ?? "\(index)"
                walk(child.value, at: path.appending(.field(label)), certain: certain && verified, depth: depth + 1)
            }
        default:
            break
        }
    }

    private static func keyDescription(_ key: Any, index: Int) -> String {
        switch key {
        case let text as String: "\"\(text.prefix(40))\""
        case let number as Int: "\(number)"
        default: "#\(index)"
        }
    }

    // MARK: - Closures

    private mutating func closure(_ value: Any, metadata: UnsafeRawPointer, at path: RetainPath, certain: Bool) {
        let convention = (metadata.load(fromByteOffset: 8, as: UInt.self) >> 16) & 0xFF
        // A thick function value is (function pointer, context), stored inline in the existential.
        let (function, context) = withUnsafeBytes(of: value) {
            ($0.load(fromByteOffset: 0, as: UInt.self), $0.load(fromByteOffset: 8, as: UInt.self))
        }
        switch convention {
        case 0:
            closure(function: function, context: context, at: path, certain: certain, keepAlive: value)
        case 1:
            // A block-convention value is the block object itself.
            if let block = UnsafeRawPointer(bitPattern: function), case .object(let object) = HeapPointer(block) {
                add(path, .object(object), certain: certain)
            }
        default:
            break
        }
    }

    /// A thick Swift function: `context` is retained by it, and is nil, one captured object, a context or a box.
    mutating func closure(function: UInt, context: UInt, at path: RetainPath, certain: Bool, keepAlive: Any) {
        guard let pointer = UnsafeRawPointer(bitPattern: context), !HeapPointer.isTaggedPointer(context) else { return }
        if firstClosure == nil { firstClosure = (function, context) }
        let name = SymbolNames.closure(at: function)
        switch HeapPointer(pointer) {
        case .object(let object):
            // A closure capturing a single object uses that object as its context.
            add(path.appending(.closure(function: name)), .object(object), certain: certain)
        case .closureContext:
            add(path, .context(pointer, kind: .closure(function: name), keepAlive: keepAlive), certain: certain)
        case .box:
            add(path, .context(pointer, kind: .box(type: Self.boxedTypeName(pointer)), keepAlive: keepAlive), certain: certain)
        case .other:
            break
        }
    }

    /// What a closure context or a box holds. Precise when the capture layout can be read from metadata;
    /// otherwise only addresses of objects already in the graph are matched, as uncertain references.
    /// A box holds one value, reported as `value`; a closure context reports each capture by index.
    mutating func captures(ofContext context: UnsafeRawPointer, isBox: Bool, keepAlive: Any) {
        let metadata = context.load(as: UnsafeRawPointer.self)
        switch SwiftMetadata.kind(of: metadata) {
        case .heapGenericLocalVariable:
            let offset = Int(metadata.load(fromByteOffset: 8, as: UInt32.self))
            let boxed = unsafeBitCast(metadata.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Any.Type.self)
            walk(loadValue(of: boxed, at: context + offset), at: RetainPath([.field("value")]))
        case .heapLocalVariable:
            if !preciseCaptures(of: context, metadata: metadata, isBox: isBox, keepAlive: keepAlive) {
                scanForKnownObjects(context, from: 16, keepAlive: keepAlive)
            }
        default:
            break
        }
    }

    private mutating func preciseCaptures(of context: UnsafeRawPointer, metadata: UnsafeRawPointer, isBox: Bool, keepAlive: Any) -> Bool {
        // HeapLocalVariable metadata: Kind(8) OffsetToFirstCapture(4) CaptureDescription(8, aligned).
        // Capture descriptor: NumCaptureTypes(4) NumMetadataSources(4) NumBindings(4), one relative mangled
        // type name per capture, then a pair of relative names (generic parameter, source) per metadata source.
        guard let descriptor = metadata.load(fromByteOffset: 16, as: UnsafeRawPointer?.self) else { return false }
        let count = Int(descriptor.load(as: UInt32.self))
        let sourceCount = Int(descriptor.load(fromByteOffset: 4, as: UInt32.self))
        let bindingCount = Int(descriptor.load(fromByteOffset: 8, as: UInt32.self))
        let first = Int(metadata.load(fromByteOffset: 8, as: UInt32.self))
        guard first + 8 * bindingCount <= malloc_size(context),
              let generic = genericArguments(descriptor, captures: count, sources: sourceCount, bindings: bindingCount,
                                             context: context, first: first) else { return false }

        enum Slot { case value(Any.Type), function, box, weak(Any.Type), skipped }
        var slots: [(slot: Slot, offset: Int)] = []
        // Generic contexts store their bindings (metadata, witness tables) before the captures.
        var offset = first + 8 * bindingCount
        for index in 0..<count {
            guard let start = descriptor.relative(at: 12 + 4 * index) else { return false }
            let name = MangledName(start)
            if name.isBox {
                offset = Self.aligned(offset, 8)
                slots.append((.box, offset))
                offset += 8
                continue
            }
            if let parameter = name.genericParameterIndex {
                guard let type = generic[parameter] else { return false }
                let layout = memoryLayout(of: type)
                offset = Self.aligned(offset, layout.alignment)
                slots.append((.value(type), offset))
                offset += layout.size
                continue
            }
            let storage = name.ownership == .strong ? name.type : name.referentType
            guard let storage else {
                // A generic function type cannot be resolved here, but every thick function has the same layout.
                guard name.ownership == .strong, name.isThickFunction else { return false }
                offset = Self.aligned(offset, 8)
                slots.append((.function, offset))
                offset += 16
                continue
            }
            let layout = memoryLayout(of: storage)
            offset = Self.aligned(offset, layout.alignment)
            switch name.ownership {
            case .strong: slots.append((.value(storage), offset))
            case .weak: slots.append((.weak(storage), offset))
            case .unowned, .unownedUnsafe: slots.append((.skipped, offset))
            }
            offset += layout.size
        }
        // The layout must fit in the allocation before anything is loaded from it.
        guard offset <= malloc_size(context) else { return false }

        for (index, (slot, offset)) in slots.enumerated() {
            let path = RetainPath([isBox ? .field("value") : .capture(index)])
            switch slot {
            case .value(let type):
                walk(loadValue(of: type, at: context + offset), at: path, depth: 1)
            case .function:
                closure(function: (context + offset).load(as: UInt.self), context: (context + offset + 8).load(as: UInt.self),
                        at: path, certain: true, keepAlive: keepAlive)
            case .box:
                let address = (context + offset).load(as: UInt.self)
                guard let box = UnsafeRawPointer(bitPattern: address) else { break }
                switch HeapPointer(box) {
                case .box, .closureContext:
                    add(path, .context(box, kind: .box(type: Self.boxedTypeName(box)), keepAlive: keepAlive))
                case .object, .other:
                    break
                }
            case .weak:
                if collectsWeak, let target = WeakReferences.load(at: context + offset) {
                    weakReferences.append((path, target))
                }
            case .skipped:
                break
            }
        }
        return true
    }

    /// Generic parameter index → metadata, for the sources that are closure bindings (`B<n>_`): the only kind
    /// a context can resolve by itself. `nil` when another kind of source is needed.
    private func genericArguments(_ descriptor: UnsafeRawPointer, captures: Int, sources: Int, bindings: Int,
                                  context: UnsafeRawPointer, first: Int) -> [Int: Any.Type]? {
        var arguments: [Int: Any.Type] = [:]
        for index in 0..<sources {
            let base = 12 + 4 * captures + 8 * index
            guard let parameter = descriptor.relative(at: base).flatMap({ MangledName($0).genericParameterIndex }),
                  let source = descriptor.relative(at: base + 4).map({ MangledName($0).plainText }),
                  source.hasPrefix("B"),
                  let binding = Int(source.dropFirst().prefix { $0.isNumber }), binding < bindings,
                  let metadata = (context + first + 8 * binding).load(as: UnsafeRawPointer?.self) else { return nil }
            arguments[parameter] = unsafeBitCast(metadata, to: Any.Type.self)
        }
        return arguments
    }

    /// Matches each word against objects already in the graph, and recognizes Swift closure contexts
    /// (a closure stored in a block made by Swift). Both as uncertain: the slot's ownership is unknown.
    mutating func scanForKnownObjects(_ pointer: UnsafeRawPointer, from start: Int, size: Int? = nil, keepAlive: Any) {
        isPartial = true
        let end = min(size ?? malloc_size(pointer), Self.maxScannedBytes)
        for offset in stride(from: start, to: end - 7, by: 8) {
            let word = pointer.load(fromByteOffset: offset, as: UInt.self)
            if let object = known(word) {
                add(RetainPath([.unverified]), object, certain: false)
            } else if let context = HeapPointer.closureContext(at: word) {
                // A thick function is (function, context): the word before names the closure.
                let function = offset >= start + 8 ? pointer.load(fromByteOffset: offset - 8, as: UInt.self) : 0
                add(RetainPath([.unverified]),
                    .context(context, kind: .closure(function: SymbolNames.closure(at: function)), keepAlive: keepAlive),
                    certain: false)
            }
        }
    }

    /// A generic box records its boxed type; a concrete one is laid out like a context with one capture.
    private static func boxedTypeName(_ box: UnsafeRawPointer) -> String {
        let metadata = box.load(as: UnsafeRawPointer.self)
        switch SwiftMetadata.kind(of: metadata) {
        case .heapGenericLocalVariable:
            return String(describing: unsafeBitCast(metadata.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Any.Type.self))
        case .heapLocalVariable:
            guard let descriptor = metadata.load(fromByteOffset: 16, as: UnsafeRawPointer?.self),
                  descriptor.load(as: UInt32.self) == 1, let name = descriptor.relative(at: 12),
                  let type = MangledName(name).type else { return "?" }
            return String(describing: type)
        default:
            return "?"
        }
    }

    private static func aligned(_ offset: Int, _ alignment: Int) -> Int {
        (offset + alignment - 1) / alignment * alignment
    }
}

extension MangledName {
    /// The type of a weak or unowned capture without its ownership marker: same size, same alignment.
    var referentType: Any.Type? {
        guard length >= 2 else { return nil }
        return _getTypeByMangledNameInContext(start.assumingMemoryBound(to: UInt8.self), UInt(length - 2),
                                              genericContext: nil, genericArguments: nil)
    }
}

#endif
