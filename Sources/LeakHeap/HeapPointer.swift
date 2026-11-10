//
//  HeapPointer.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// What a pointer known to be a live heap object points to, read without sending any message.
enum HeapPointer {
    case object(AnyObject)
    /// A Swift closure context: what the closure captured.
    case closureContext
    /// The heap box of a captured `var`.
    case box
    case other

    init(_ pointer: UnsafeRawPointer) {
        let address = UInt(bitPattern: pointer)
        guard !Self.isTaggedPointer(address) else { self = .other; return }
        let isa = pointer.load(as: UInt.self)
        // Objective-C non-pointer isa sets bit 0; Swift objects and raw isa hold a real metadata pointer.
        if isa & 1 == 1 {
            self = .object(Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue())
            return
        }
        guard let metadata = UnsafeRawPointer(bitPattern: isa) else { self = .other; return }
        if SwiftMetadata.isClass(metadata) {
            self = .object(Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue())
            return
        }
        switch SwiftMetadata.kind(of: metadata) {
        case .heapLocalVariable: self = .closureContext
        case .heapGenericLocalVariable: self = .box
        default: self = .other
        }
    }

    /// A Swift closure context at an address read from memory whose layout is unknown, or `nil`. The word
    /// must start a live malloc block, and its metadata must be static data in a loaded image, before
    /// anything is dereferenced. Objects are never accepted this way: a random word could pass for one.
    static func closureContext(at address: UInt) -> UnsafeRawPointer? {
        guard !isTaggedPointer(address), let pointer = UnsafeRawPointer(bitPattern: address),
              malloc_size(pointer) >= 16 else { return nil }
        let isa = pointer.load(as: UInt.self)
        guard isa & 1 == 0, SymbolNames.isInLoadedImage(isa), let metadata = UnsafeRawPointer(bitPattern: isa),
              SwiftMetadata.kind(of: metadata) == .heapLocalVariable else { return nil }
        return pointer
    }

    /// Tagged pointers hold their value inline: nothing to follow, and nothing to dereference.
    static func isTaggedPointer(_ address: UInt) -> Bool {
        #if arch(arm64)
        address >> 63 == 1
        #else
        address & 1 == 1
        #endif
    }
}

/// A class instance or a closure context held without keeping it alive. An instance through `weak`; a
/// context, which a weak reference cannot point to, through its unowned count, checked with `swift_tryRetain`.
package final class UnretainedHeapReference: @unchecked Sendable {
    private enum Target {
        case object(Weak)
        case context(UnsafeRawPointer)
    }

    private final class Weak { weak var object: AnyObject? }

    /// Keeps a context alive for as long as it lives.
    private final class Retained: @unchecked Sendable {
        let pointer: UnsafeRawPointer
        init(_ pointer: UnsafeRawPointer) { self.pointer = pointer }
        deinit { Runtime.shared?.release(pointer) }
    }

    private let target: Target

    /// `address` must point to a live object or context while this runs.
    package init?(address: UInt) {
        guard let pointer = UnsafeRawPointer(bitPattern: address), !HeapPointer.isTaggedPointer(address) else { return nil }
        switch HeapPointer(pointer) {
        case .object(let object):
            let weak = Weak()
            weak.object = object
            target = .object(weak)
        case .closureContext, .box:
            guard let runtime = Runtime.shared else { return nil }
            runtime.unownedRetain(pointer)
            target = .context(pointer)
        case .other:
            return nil
        }
    }

    deinit {
        if case .context(let pointer) = target { Runtime.shared?.unownedRelease(pointer) }
    }

    /// Something that keeps the target alive while held, or `nil` once the target is gone.
    package func retained() -> Any? {
        switch target {
        case .object(let weak):
            return weak.object
        case .context(let pointer):
            guard let runtime = Runtime.shared, runtime.tryRetain(pointer) != nil else { return nil }
            return Retained(pointer)
        }
    }

    private final class Runtime: @unchecked Sendable {
        private typealias Unary = @convention(c) (UnsafeRawPointer) -> Void
        /// Returns the object retained, or null when it is already being deinitialized.
        private typealias TryRetain = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?

        static let shared = Runtime()

        let unownedRetain: (UnsafeRawPointer) -> Void
        let unownedRelease: (UnsafeRawPointer) -> Void
        let release: (UnsafeRawPointer) -> Void
        let tryRetain: (UnsafeRawPointer) -> UnsafeRawPointer?

        private init?() {
            let handle = UnsafeMutableRawPointer(bitPattern: -2)
            guard let unownedRetain = dlsym(handle, "swift_unownedRetain"), let unownedRelease = dlsym(handle, "swift_unownedRelease"),
                  let release = dlsym(handle, "swift_release"), let tryRetain = dlsym(handle, "swift_tryRetain") else { return nil }
            self.unownedRetain = unsafeBitCast(unownedRetain, to: Unary.self)
            self.unownedRelease = unsafeBitCast(unownedRelease, to: Unary.self)
            self.release = unsafeBitCast(release, to: Unary.self)
            self.tryRetain = unsafeBitCast(tryRetain, to: TryRetain.self)
        }
    }
}

/// Weak references read without knowing whether the referent is a Swift or an Objective-C object.
enum WeakReferences {
    private typealias LoadStrong = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private static let loadStrong: LoadStrong? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_unknownObjectWeakLoadStrong")
        .map { unsafeBitCast($0, to: LoadStrong.self) }

    /// The object a weak reference stored at `slot` points to, retained, or `nil` once it is gone.
    static func load(at slot: UnsafeRawPointer) -> AnyObject? {
        guard let loadStrong, let object = loadStrong(slot) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(object).takeRetainedValue()
    }
}

/// `true` when `cls` is `base` or inherits from it, read from the class chain: messaging a proxy forwards it.
func inherits(_ cls: AnyClass, from base: AnyClass) -> Bool {
    var current: AnyClass? = cls
    while let candidate = current {
        if candidate === base { return true }
        current = class_getSuperclass(candidate)
    }
    return false
}

/// Copies the value of type `type` stored at `pointer`, retaining what it holds.
func loadValue(of type: Any.Type, at pointer: UnsafeRawPointer) -> Any {
    func load<T>(_: T.Type) -> Any { pointer.load(as: T.self) }
    return _openExistential(type, do: load)
}

func memoryLayout(of type: Any.Type) -> (size: Int, alignment: Int) {
    func layout<T>(_: T.Type) -> (size: Int, alignment: Int) { (MemoryLayout<T>.size, MemoryLayout<T>.alignment) }
    return _openExistential(type, do: layout)
}

#endif
