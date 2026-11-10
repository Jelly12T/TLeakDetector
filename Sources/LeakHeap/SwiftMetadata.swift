//
//  SwiftMetadata.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// Reads Swift runtime metadata (swift/ABI/Metadata.h, RemoteInspection/Records.h, 64-bit with ObjC interop).
/// Layouts verified by the FieldOwnership spike, ADR 002.
enum SwiftMetadata {
    enum Ownership {
        case strong, weak, unowned, unownedUnsafe
    }

    struct Field {
        let name: String
        let ownership: Ownership
    }

    /// A stored property as the runtime lays it out: generic arguments substituted, superclasses included.
    struct StoredField {
        let name: String
        let offset: Int
        let type: Any.Type
        let ownership: Ownership
    }

    enum Kind: UInt {
        case `struct` = 0x200
        case `enum` = 0x201
        case optional = 0x202
        case tuple = 0x301
        case function = 0x302
        case heapLocalVariable = 0x400
        case heapGenericLocalVariable = 0x500
    }

    /// `nil` for classes: their first word is an isa pointer, not a kind.
    static func kind(of metadata: UnsafeRawPointer) -> Kind? {
        Kind(rawValue: metadata.load(as: UInt.self))
    }

    static func isClass(_ metadata: UnsafeRawPointer) -> Bool {
        metadata.load(as: UInt.self) > 0x7FF
    }

    /// Objective-C classes reach Swift as ObjCClassWrapper metadata (kind 0x305), never as Swift class
    /// metadata, so reading Swift class fields from them would read past the wrapper.
    static func isSwiftClass(_ cls: AnyClass) -> Bool {
        isClass(unsafeBitCast(cls, to: UnsafeRawPointer.self))
    }

    /// Stored properties declared by this class itself, in declaration order: the order of its Mirror children.
    /// `nil` when its module was built without reflection metadata.
    static func fields(ofClass cls: AnyClass) -> [Field]? {
        let metadata = unsafeBitCast(cls, to: UnsafeRawPointer.self)
        return FieldCache.shared.fields(of: metadata) {
            metadata.load(fromByteOffset: 64, as: UnsafeRawPointer?.self).flatMap(readFields)
        }
    }

    /// `Outer.Inner` and its module, read from the class's context descriptors: asking the Swift runtime
    /// for a class name costs about half a millisecond the first time.
    static func name(ofSwiftClass cls: AnyClass) -> (name: String, module: String?)? {
        let metadata = unsafeBitCast(cls, to: UnsafeRawPointer.self)
        guard isClass(metadata), var context = metadata.load(fromByteOffset: 64, as: UnsafeRawPointer?.self) else { return nil }
        var names: [String] = []
        // Context descriptor: Flags(4, kind in the low 5 bits) Parent(4, indirectable) Name(4, types and modules).
        while true {
            let kind = context.load(as: UInt32.self) & 0x1F
            if kind == 0 || kind >= 16, let name = context.relative(at: 8) {
                let text = String(cString: name.assumingMemoryBound(to: CChar.self))
                if kind == 0 { return (names.reversed().joined(separator: "."), text) }
                names.append(text)
            }
            let offset = context.load(fromByteOffset: 4, as: Int32.self)
            guard offset != 0 else { break }
            let target = context + 4 + Int(offset & ~1)
            guard let parent = offset & 1 == 1 ? target.load(as: UnsafeRawPointer?.self) : target else { break }
            context = parent
        }
        return names.isEmpty ? nil : (names.reversed().joined(separator: "."), nil)
    }

    /// Every stored property of a Swift class and its Swift superclasses, superclass first. Read from the
    /// runtime, not from `Mirror`: a custom mirror shows what its author chose, and building one per object
    /// costs. Ownership comes from each class's field metadata. `nil` without reflection metadata.
    static func storedFields(ofClass cls: AnyClass) -> [StoredField]? {
        let metadata = unsafeBitCast(cls, to: UnsafeRawPointer.self)
        return StoredFieldCache.shared.fields(of: metadata) {
            guard let runtime = ReflectionRuntime.shared else { return nil }
            var levels: [[Field]] = []
            var current: AnyClass? = cls
            while let level = current, isSwiftClass(level) {
                guard let fields = fields(ofClass: level) else { return nil }
                levels.append(fields)
                current = class_getSuperclass(level)
            }
            let declared = levels.reversed().flatMap { $0 }
            guard runtime.count(metadata) == declared.count else { return nil }
            var stored: [StoredField] = []
            for (index, field) in declared.enumerated() {
                guard let child = runtime.child(metadata, index), child.name == field.name else { return nil }
                stored.append(StoredField(name: field.name, offset: runtime.offset(metadata, index), type: child.type,
                                          ownership: field.ownership))
            }
            return stored
        }
    }

    static func fields(ofStruct type: Any.Type) -> [Field]? {
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        guard kind(of: metadata) == .struct else { return nil }
        return FieldCache.shared.fields(of: metadata) {
            metadata.load(fromByteOffset: 8, as: UnsafeRawPointer?.self).flatMap(readFields)
        }
    }

    private static func readFields(descriptor: UnsafeRawPointer) -> [Field]? {
        // Type context descriptor: Flags, Parent, Name, AccessFunction, Fields (4 bytes each).
        guard let fieldDescriptor = descriptor.relative(at: 16) else { return nil }
        // Field descriptor: MangledTypeName(4) Superclass(4) Kind(2) FieldRecordSize(2) NumFields(4), records.
        let recordSize = Int(fieldDescriptor.load(fromByteOffset: 10, as: UInt16.self))
        let count = Int(fieldDescriptor.load(fromByteOffset: 12, as: UInt32.self))
        return (0..<count).map { index in
            // Field record: Flags(4) MangledTypeName(4) FieldName(4).
            let record = fieldDescriptor + 16 + index * recordSize
            let name = record.relative(at: 8).map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
            let ownership = record.relative(at: 4).map { MangledName($0).ownership } ?? .strong
            return Field(name: name, ownership: ownership)
        }
    }
}

/// A mangled type name as stored in metadata: bytes 0x01–0x17 start a 4-byte relative symbolic
/// reference, 0x18–0x1F an 8-byte absolute one, and a 0 byte ends it. Plain C-string reading is wrong.
struct MangledName {
    let start: UnsafeRawPointer
    let length: Int
    let ownership: SwiftMetadata.Ownership
    /// `Xx`: a captured `var`, stored as a pointer to a heap box.
    let isBox: Bool

    init(_ start: UnsafeRawPointer) {
        self.start = start
        var offset = 0
        var last: (UInt8, UInt8) = (0, 0)
        while true {
            let byte = start.load(fromByteOffset: offset, as: UInt8.self)
            switch byte {
            case 0:
                break
            case 0x01...0x17:
                offset += 5; last = (0, 0); continue
            case 0x18...0x1F:
                offset += 9; last = (0, 0); continue
            default:
                last = (last.1, byte); offset += 1; continue
            }
            break
        }
        length = offset
        let isOwnershipMarker = last.0 == UInt8(ascii: "X")
        switch isOwnershipMarker ? last.1 : 0 {
        case UInt8(ascii: "w"): ownership = .weak
        case UInt8(ascii: "o"): ownership = .unowned
        case UInt8(ascii: "u"): ownership = .unownedUnsafe
        default: ownership = .strong
        }
        isBox = isOwnershipMarker && last.1 == UInt8(ascii: "x")
    }

    /// `x` is τ_0_0, `q_` τ_0_1, `q0_` τ_0_2: a generic parameter of the closure's own function. `nil` otherwise.
    var genericParameterIndex: Int? {
        let text = plainText
        if text == "x" { return 0 }
        guard text.hasPrefix("q"), text.hasSuffix("_") else { return nil }
        let digits = text.dropFirst().dropLast()
        if digits.isEmpty { return 1 }
        return Int(digits).map { $0 + 2 }
    }

    /// A thick Swift function (`@callee_guaranteed` or `@callee_owned`): stored as a function pointer and a
    /// retained context, whatever its parameter and result types. Lets generic function captures be read.
    var isThickFunction: Bool {
        plainText.range(of: #"I(e)?[gx][A-Za-z]*_$"#, options: .regularExpression) != nil
    }

    /// The name with symbolic references replaced by `#`, for matching shapes.
    var plainText: String {
        var text = ""
        var offset = 0
        while offset < length {
            let byte = start.load(fromByteOffset: offset, as: UInt8.self)
            switch byte {
            case 0x01...0x17: text += "#"; offset += 5
            case 0x18...0x1F: text += "#"; offset += 9
            default: text.unicodeScalars.append(UnicodeScalar(byte)); offset += 1
            }
        }
        return text
    }

    /// Non-generic names only: generic ones need the generic arguments of the context.
    var type: Any.Type? {
        _getTypeByMangledNameInContext(start.assumingMemoryBound(to: UInt8.self), UInt(length),
                                       genericContext: nil, genericArguments: nil)
    }
}

/// What `Mirror` itself uses (swift/stdlib/public/runtime/ReflectionMirror.cpp), reached by name: the
/// functions are exported but not declared in any SDK module. Plain pointer and integer arguments, so the
/// Swift calling convention matches C here.
private struct ReflectionRuntime: @unchecked Sendable {
    private typealias Count = @convention(c) (UnsafeRawPointer) -> Int
    /// The third argument is a `_FieldReflectionMetadata`: name(8) freeFunc(8) isStrong(1) isVar(1).
    private typealias ChildMetadata = @convention(c) (UnsafeRawPointer, Int, UnsafeMutableRawPointer) -> UnsafeRawPointer?
    private typealias Offset = @convention(c) (UnsafeRawPointer, Int) -> Int
    private typealias FreeName = @convention(c) (UnsafePointer<CChar>?) -> Void

    static let shared = ReflectionRuntime()

    let count: (UnsafeRawPointer) -> Int
    let offset: (UnsafeRawPointer, Int) -> Int
    private let childMetadata: ChildMetadata

    private init?() {
        let runtime = UnsafeMutableRawPointer(bitPattern: -2)
        guard let count = dlsym(runtime, "swift_reflectionMirror_recursiveCount"),
              let child = dlsym(runtime, "swift_reflectionMirror_recursiveChildMetadata"),
              let offset = dlsym(runtime, "swift_reflectionMirror_recursiveChildOffset") else { return nil }
        self.count = unsafeBitCast(count, to: Count.self)
        self.offset = unsafeBitCast(offset, to: Offset.self)
        childMetadata = unsafeBitCast(child, to: ChildMetadata.self)
    }

    func child(_ metadata: UnsafeRawPointer, _ index: Int) -> (name: String, type: Any.Type)? {
        let field = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        defer { field.deallocate() }
        field.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
        guard let type = childMetadata(metadata, index, field) else { return nil }
        let name = field.load(as: UnsafePointer<CChar>?.self)
        let text = name.map { String(cString: $0) } ?? ""
        if let free = field.load(fromByteOffset: 8, as: UnsafeRawPointer?.self) { unsafeBitCast(free, to: FreeName.self)(name) }
        return (text, unsafeBitCast(type, to: Any.Type.self))
    }
}

private final class StoredFieldCache: @unchecked Sendable {
    static let shared = StoredFieldCache()
    private let lock = NSLock()
    private var entries: [UnsafeRawPointer: [SwiftMetadata.StoredField]?] = [:]

    func fields(of metadata: UnsafeRawPointer, read: () -> [SwiftMetadata.StoredField]?) -> [SwiftMetadata.StoredField]? {
        lock.lock()
        if let cached = entries[metadata] { lock.unlock(); return cached }
        lock.unlock()
        let fields = read()
        lock.lock()
        entries[metadata] = fields
        lock.unlock()
        return fields
    }
}

private final class FieldCache: @unchecked Sendable {
    static let shared = FieldCache()
    private let lock = NSLock()
    private var entries: [UnsafeRawPointer: [SwiftMetadata.Field]?] = [:]

    func fields(of metadata: UnsafeRawPointer, read: () -> [SwiftMetadata.Field]?) -> [SwiftMetadata.Field]? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[metadata] { return cached }
        let fields = read()
        entries[metadata] = fields
        return fields
    }
}

extension UnsafeRawPointer {
    /// Resolves a 32-bit relative direct pointer stored at `offset`.
    func relative(at offset: Int) -> UnsafeRawPointer? {
        let delta = load(fromByteOffset: offset, as: Int32.self)
        return delta == 0 ? nil : self + offset + Int(delta)
    }
}

#endif
