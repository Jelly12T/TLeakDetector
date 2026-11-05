//
//  FieldOwnershipReader.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — reference only. Reads stored-property ownership (strong/weak/unowned)
//  straight from Swift reflection metadata:
//
//      metadata ──► type context descriptor ──► field descriptor ──► field records
//
//  Layouts follow swift/include/swift/ABI/Metadata.h and Records.h (64-bit, ObjC interop).
//  Ownership comes from the field's mangled type name suffix (docs/ABI/Mangling.rst):
//      type 'Xw'  @weak            type 'Xo'  @unowned            type 'Xu'  @unowned(unsafe)
//

import Foundation

public enum Ownership: String {
    case strong
    case weak
    case unowned
    case unownedUnsafe = "unowned(unsafe)"
}

public struct FieldInfo {
    /// Name of the type that declares the field (superclass fields carry the superclass name).
    public let declaringType: String
    public let name: String
    /// Mangled type name, symbolic references printed as `{direct}` / `{indirect}` / `{absolute}`.
    public let mangledTypeName: String
    public let hasSymbolicReference: Bool
    public let ownership: Ownership
    public let isVar: Bool
}

public struct TypeFields {
    public let typeName: String
    /// How the walk went, e.g. ["class SwiftSubclass", "class SwiftBase", "stop: ObjC class NSObject"].
    public let path: [String]
    public let fields: [FieldInfo]
    /// Set when the walk could not reach a field descriptor.
    public let failure: String?
}

public enum FieldOwnershipReader {
    public static func read(_ value: Any) -> TypeFields {
        read(type: type(of: value))
    }

    public static func read(type: Any.Type) -> TypeFields {
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        var path: [String] = []
        var fields: [FieldInfo] = []

        switch MetadataKind(metadata) {
        case .struct, .enum:
            guard let descriptor = metadata.loadPointer(at: 8) else {
                return TypeFields(typeName: "\(type)", path: ["no type descriptor"], fields: [], failure: "no type descriptor")
            }
            path.append("value type → descriptor \(descriptor.name)")
            switch readFields(descriptor: descriptor) {
            case .success(let f): fields = f
            case .failure(let reason):
                return TypeFields(typeName: "\(type)", path: path, fields: [], failure: reason.text)
            }

        case .class:
            // Walk the class chain: own fields first, then each Swift superclass.
            var current: UnsafeRawPointer? = metadata
            while let cls = current {
                guard isSwiftClass(cls) else {
                    path.append("stop: ObjC class \(NSStringFromClass(unsafeBitCast(cls, to: AnyClass.self)))")
                    break
                }
                guard let descriptor = cls.loadPointer(at: 64) else {
                    return TypeFields(typeName: "\(type)", path: path + ["no class descriptor"], fields: fields, failure: "no class descriptor")
                }
                path.append("class \(descriptor.name)")
                switch readFields(descriptor: descriptor) {
                case .success(let f): fields += f
                case .failure(let reason):
                    return TypeFields(typeName: "\(type)", path: path, fields: fields, failure: reason.text)
                }
                current = cls.loadPointer(at: 8)   // superclass
            }

        case .other(let kind):
            return TypeFields(typeName: "\(type)", path: ["metadata kind 0x\(String(kind, radix: 16))"], fields: [], failure: "unsupported metadata kind")
        }

        return TypeFields(typeName: "\(type)", path: path, fields: fields, failure: nil)
    }

    // MARK: - Field descriptor

    private struct Failure: Error { let text: String }

    private static func readFields(descriptor: UnsafeRawPointer) -> Result<[FieldInfo], Failure> {
        // TargetTypeContextDescriptor: Flags(4) Parent(4) Name(4) AccessFunction(4) Fields(4)
        guard let fieldDescriptor = descriptor.relative(at: 16) else {
            return .failure(Failure(text: "Fields pointer is null (reflection metadata not emitted)"))
        }
        // FieldDescriptor: MangledTypeName(4) Superclass(4) Kind(2) FieldRecordSize(2) NumFields(4) records...
        let recordSize = Int(fieldDescriptor.load(fromByteOffset: 10, as: UInt16.self))
        let count = Int(fieldDescriptor.load(fromByteOffset: 12, as: UInt32.self))
        let declaringType = descriptor.name
        var result: [FieldInfo] = []
        for index in 0..<count {
            // FieldRecord: Flags(4) MangledTypeName(4) FieldName(4)
            let record = fieldDescriptor + 16 + index * recordSize
            let flags = record.load(as: UInt32.self)
            let mangled = record.relative(at: 4).map(MangledName.init) ?? MangledName.empty
            let name = record.relative(at: 8).map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
            result.append(FieldInfo(
                declaringType: declaringType,
                name: name,
                mangledTypeName: mangled.display,
                hasSymbolicReference: mangled.hasSymbolicReference,
                ownership: mangled.ownership,
                isVar: flags & 0x2 != 0))
        }
        return .success(result)
    }

    // MARK: - Metadata helpers

    private enum MetadataKind {
        case `class`, `struct`, `enum`, other(UInt)

        init(_ metadata: UnsafeRawPointer) {
            let raw = metadata.load(as: UInt.self)
            switch raw {
            case 0x200: self = .struct
            case 0x201, 0x202: self = .enum           // enum, Optional
            case 0: self = .class                      // class without ObjC interop
            case let isa where isa > 0x7FF: self = .class   // first word is an isa pointer
            default: self = .other(raw)
            }
        }
    }

    /// Swift classes set bit 0 (pre-stable) or bit 1 (stable ABI) of the rodata pointer.
    private static func isSwiftClass(_ cls: UnsafeRawPointer) -> Bool {
        cls.load(fromByteOffset: 32, as: UInt.self) & 0x3 != 0
    }
}

// MARK: - Mangled type names

/// Walks a mangled name the way the runtime does: bytes 0x01–0x17 start a 4-byte relative
/// symbolic reference, 0x18–0x1F an 8-byte absolute one; a 0 byte ends the string.
struct MangledName {
    let display: String
    let hasSymbolicReference: Bool
    let ownership: Ownership

    static let empty = MangledName(display: "", hasSymbolicReference: false, ownership: .strong)

    init(display: String, hasSymbolicReference: Bool, ownership: Ownership) {
        self.display = display
        self.hasSymbolicReference = hasSymbolicReference
        self.ownership = ownership
    }

    init(_ start: UnsafeRawPointer) {
        var display = ""
        var tokens: [UInt8?] = []   // nil = symbolic reference
        var symbolic = false
        var offset = 0
        while true {
            let byte = start.load(fromByteOffset: offset, as: UInt8.self)
            switch byte {
            case 0:
                break
            case 0x01...0x17:
                display += byte == 0x01 ? "{direct}" : byte == 0x02 ? "{indirect}" : "{sym 0x\(String(byte, radix: 16))}"
                tokens.append(nil); symbolic = true; offset += 5; continue
            case 0x18...0x1F:
                display += "{absolute}"
                tokens.append(nil); symbolic = true; offset += 9; continue
            default:
                display.append(Character(UnicodeScalar(byte)))
                tokens.append(byte); offset += 1; continue
            }
            break
        }
        var ownership = Ownership.strong
        if tokens.count >= 2, tokens[tokens.count - 2] == UInt8(ascii: "X"), let last = tokens.last ?? nil {
            switch last {
            case UInt8(ascii: "w"): ownership = .weak
            case UInt8(ascii: "o"): ownership = .unowned
            case UInt8(ascii: "u"): ownership = .unownedUnsafe
            default: break
            }
        }
        self.init(display: display, hasSymbolicReference: symbolic, ownership: ownership)
    }
}

// MARK: - Raw pointer helpers

extension UnsafeRawPointer {
    /// Resolves a 32-bit relative direct pointer stored at `offset`.
    func relative(at offset: Int) -> UnsafeRawPointer? {
        let delta = load(fromByteOffset: offset, as: Int32.self)
        return delta == 0 ? nil : self + offset + Int(delta)
    }

    func loadPointer(at offset: Int) -> UnsafeRawPointer? {
        load(fromByteOffset: offset, as: UnsafeRawPointer?.self)
    }

    /// Name of a type context descriptor (Name is a relative pointer at offset 8).
    var name: String {
        relative(at: 8).map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "?"
    }
}
