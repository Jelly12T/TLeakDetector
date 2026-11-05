//
//  RuntimeFieldReader.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — cross-check. Asks the Swift runtime instead of parsing metadata by hand.
//  These are the entry points the stdlib's own `_forEachField` (SPI Reflection) uses.
//  They report `isStrong` (strong vs weak/unowned) and the field's type metadata.
//

import Foundation

public struct RuntimeField {
    public let name: String
    public let isStrong: Bool
    public let isVar: Bool
    public let type: Any.Type
}

public enum RuntimeFieldReader {
    /// Includes superclass fields for classes (superclass first), like `_forEachField`.
    public static func fields(of type: Any.Type) -> [RuntimeField] {
        let count = _recursiveCount(type)
        return (0..<count).map { index in
            var field = FieldReflectionMetadata()
            let childType = _recursiveChildMetadata(type, index: index, fieldMetadata: &field)
            defer { field.freeFunc?(field.name) }
            return RuntimeField(
                name: field.name.map { String(cString: $0) } ?? "",
                isStrong: field.isStrong,
                isVar: field.isVar,
                type: childType)
        }
    }
}

// Mirrors `_FieldReflectionMetadata` in stdlib/public/core/ReflectionMirror.swift.
struct FieldReflectionMetadata {
    var name: UnsafePointer<CChar>? = nil
    var freeFunc: (@convention(c) (UnsafePointer<CChar>?) -> Void)? = nil
    var isStrong: Bool = false
    var isVar: Bool = false
}

@_silgen_name("swift_reflectionMirror_recursiveCount")
func _recursiveCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
func _recursiveChildMetadata(
    _: Any.Type,
    index: Int,
    fieldMetadata: UnsafeMutablePointer<FieldReflectionMetadata>
) -> Any.Type
