//
//  AssociatedObjects.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import MachO

/// The Objective-C runtime cannot list an object's associated objects, so calls to
/// `objc_setAssociatedObject` are intercepted and the keys set with a retaining policy are recorded
/// on the owner itself. Values are always read back through `objc_getAssociatedObject`: nothing is
/// kept that could dangle, and a record dies with its owner.
package enum AssociatedObjects {
    private typealias SetAssociatedObject = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UInt) -> Void

    nonisolated(unsafe) private static var original: SetAssociatedObject?
    nonisolated(unsafe) private static var includeImage: (@Sendable (String) -> Bool)?
    nonisolated(unsafe) private static let recordKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private static let lock = NSLock()

    package static var isInstalled: Bool { original != nil }

    /// Records associations set from now on by code in images whose path `includeImage` accepts.
    /// Calls made by other images, e.g. system frameworks, and earlier calls are not seen.
    package static func install(includeImage: @escaping @Sendable (String) -> Bool = AssociatedObjects.isAppImage) {
        lock.lock()
        defer { lock.unlock() }
        guard original == nil,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_setAssociatedObject") else { return }
        original = unsafeBitCast(symbol, to: SetAssociatedObject.self)
        Self.includeImage = includeImage
        // Called now for every loaded image, then for each image loaded later.
        _dyld_register_func_for_add_image { header, slide in
            guard let header, let filter = AssociatedObjects.includeImage else { return }
            var info = Dl_info()
            guard dladdr(header, &info) != 0, let path = info.dli_fname, filter(String(cString: path)) else { return }
            SymbolRebinder.rebind("objc_setAssociatedObject", to: unsafeBitCast(AssociatedObjects.hook, to: UnsafeRawPointer.self),
                                  in: header, slide: slide)
        }
    }

    /// The app executable, its debug dylib and its embedded frameworks.
    package static let isAppImage: @Sendable (String) -> Bool = { path in
        path.hasPrefix(Bundle.main.bundlePath + "/")
    }

    /// Values associated with `object` under a retaining policy, by key name.
    static func strongValues(of object: AnyObject) -> [(key: String, value: AnyObject)] {
        guard isInstalled, let record = objc_getAssociatedObject(object, recordKey) as? Record else { return [] }
        return record.keys.compactMap { key in
            objc_getAssociatedObject(object, key).map { (SymbolNames.variable(at: UInt(bitPattern: key)), $0 as AnyObject) }
        }
    }

    private static let hook: SetAssociatedObject = { object, key, value, policy in
        AssociatedObjects.original?(object, key, value, policy)
        guard let object, let key else { return }
        // OBJC_ASSOCIATION_ASSIGN is 0; every other policy retains or copies the value.
        AssociatedObjects.record(owner: object, key: key, retained: value != nil && policy != 0)
    }

    private static func record(owner pointer: UnsafeRawPointer, key: UnsafeRawPointer, retained: Bool) {
        let owner = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        lock.lock()
        defer { lock.unlock() }
        if let record = objc_getAssociatedObject(owner, recordKey) as? Record {
            record.update(key, retained: retained)
        } else if retained, let original {
            let record = Record()
            record.update(key, retained: true)
            // Through the original function: this module's own call would come back to the hook.
            original(pointer, recordKey, UnsafeRawPointer(Unmanaged.passUnretained(record).toOpaque()), 1)
        }
    }

    private final class Record: @unchecked Sendable {
        private let lock = NSLock()
        private var retainedKeys: [UnsafeRawPointer] = []

        var keys: [UnsafeRawPointer] {
            lock.lock()
            defer { lock.unlock() }
            return retainedKeys
        }

        func update(_ key: UnsafeRawPointer, retained: Bool) {
            lock.lock()
            defer { lock.unlock() }
            retainedKeys.removeAll { $0 == key }
            if retained { retainedKeys.append(key) }
        }
    }
}

#endif
