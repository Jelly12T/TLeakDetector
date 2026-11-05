//
//  PropertyScanner.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED

/// Finds class instances held in an object's stored properties, via Mirror.
///
/// MVP limits: direct values and Optionals only (no arrays/dictionaries), one level deep.
/// Mirror cannot tell weak from strong (see ADR 002), so weak properties are returned too.
package enum PropertyScanner {
    package struct Found {
        package let label: String
        package let object: AnyObject
    }

    /// Stored properties of `object` and its superclasses whose value is a class instance
    /// accepted by `include` (e.g. "type lives in the app bundle").
    package static func classProperties(of object: AnyObject, include: (AnyClass) -> Bool) -> [Found] {
        var found: [Found] = []
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children {
                guard let value = classInstance(in: child.value), include(type(of: value)) else { continue }
                found.append(Found(label: displayLabel(child.label), object: value))
            }
            mirror = current.superclassMirror
        }
        return found
    }

    /// Unwraps Optionals; returns nil for value types.
    static func classInstance(in value: Any) -> AnyObject? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.flatMap { classInstance(in: $0.value) }
        }
        guard type(of: value) is AnyClass else { return nil }
        return value as AnyObject
    }

    /// `$__lazy_storage_$_foo` → `foo`.
    static func displayLabel(_ label: String?) -> String {
        guard let label else { return "?" }
        let lazyPrefix = "$__lazy_storage_$_"
        return label.hasPrefix(lazyPrefix) ? String(label.dropFirst(lazyPrefix.count)) : label
    }
}

#endif
