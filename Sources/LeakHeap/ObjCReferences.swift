//
//  ObjCReferences.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import LeakGraph

enum ObjCReferences {
    private static let blockClass: AnyClass? = NSClassFromString("NSBlock")

    static func isBlock(_ cls: AnyClass) -> Bool {
        blockClass.map { inherits(cls, from: $0) } ?? false
    }

    // MARK: - Ivars

    /// Object ivars declared by `cls` itself that its ARC ivar layout marks strong. A class with no strong
    /// ivar has no layout; weak and `__unsafe_unretained` ivars are never in it, so they are never read.
    static func strongIvars(of cls: AnyClass) -> [(name: String, ivar: Ivar)] {
        IvarCache.shared.ivars(of: cls) {
            guard let layout = class_getIvarLayout(cls) else { return [] }
            var count: UInt32 = 0
            guard let list = class_copyIvarList(cls, &count), count > 0 else { return [] }
            defer { free(list) }
            let ivars = (0..<Int(count)).map { list[$0] }

            // Each layout byte: high nibble = words to skip, low nibble = strong words, from the first ivar.
            var strongWords = Set<Int>()
            var word = ivar_getOffset(ivars[0]) / MemoryLayout<UnsafeRawPointer>.size
            var cursor = layout
            while cursor.pointee != 0 {
                word += Int(cursor.pointee >> 4)
                for _ in 0..<Int(cursor.pointee & 0xF) {
                    strongWords.insert(word)
                    word += 1
                }
                cursor += 1
            }
            return ivars.compactMap { ivar in
                guard let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == CChar(UInt8(ascii: "@")),
                      strongWords.contains(ivar_getOffset(ivar) / MemoryLayout<UnsafeRawPointer>.size),
                      let name = ivar_getName(ivar) else { return nil }
                return (String(cString: name), ivar)
            }
        }
    }

    // MARK: - Collections

    private static let hashTableClass: AnyClass = NSHashTable<AnyObject>.self
    private static let mapTableClass: AnyClass = NSMapTable<AnyObject, AnyObject>.self

    /// `false` when `object` is not a collection. Weak hash and map tables hold nothing strongly.
    static func collectionReferences(of object: AnyObject, into collector: inout ReferenceCollector) -> Bool {
        let cls: AnyClass = type(of: object)
        let limit = ReferenceCollector.maxElements
        if inherits(cls, from: hashTableClass) {
            let table = unsafeDowncast(object, to: NSHashTable<AnyObject>.self)
            if retains(table.pointerFunctions) {
                for (index, element) in table.allObjects.prefix(limit).enumerated() {
                    collector.add(RetainPath([.element(index)]), .object(element))
                }
            }
        } else if inherits(cls, from: mapTableClass) {
            let table = unsafeDowncast(object, to: NSMapTable<AnyObject, AnyObject>.self)
            let keys = retains(table.keyPointerFunctions), values = retains(table.valuePointerFunctions)
            let allKeys = table.keyEnumerator().allObjects.prefix(limit).map { $0 as AnyObject }
            for (index, key) in allKeys.enumerated() {
                if keys { collector.add(RetainPath([.key(index)]), .object(key)) }
                if values, let value = table.object(forKey: key) {
                    collector.add(RetainPath([.value(key: description(of: key, index: index))]), .object(value))
                }
            }
        } else if inherits(cls, from: NSArray.self) {
            for (index, element) in unsafeDowncast(object, to: NSArray.self).prefix(limit).enumerated() {
                collector.add(RetainPath([.element(index)]), .object(element as AnyObject))
            }
        } else if inherits(cls, from: NSOrderedSet.self) {
            for (index, element) in unsafeDowncast(object, to: NSOrderedSet.self).prefix(limit).enumerated() {
                collector.add(RetainPath([.element(index)]), .object(element as AnyObject))
            }
        } else if inherits(cls, from: NSSet.self) {
            for (index, element) in unsafeDowncast(object, to: NSSet.self).prefix(limit).enumerated() {
                collector.add(RetainPath([.element(index)]), .object(element as AnyObject))
            }
        } else if inherits(cls, from: NSDictionary.self) {
            for (index, (key, value)) in unsafeDowncast(object, to: NSDictionary.self).prefix(limit).enumerated() {
                collector.add(RetainPath([.key(index)]), .object(key as AnyObject))
                collector.add(RetainPath([.value(key: description(of: key, index: index))]), .object(value as AnyObject))
            }
        } else {
            return false
        }
        return true
    }

    /// Strong pointer functions retain on insert; weak and opaque ones have no acquire function.
    private static func retains(_ functions: NSPointerFunctions) -> Bool {
        functions.acquireFunction != nil
    }

    private static func description(of key: Any, index: Int) -> String {
        if let text = key as? String { return "\"\(text.prefix(40))\"" }
        if let number = key as? NSNumber { return number.stringValue }
        return "#\(index)"
    }

    // MARK: - Blocks

    /// What a block captured. Clang's extended layout tells strong captures apart; without it (blocks made by
    /// Swift from closures) only addresses of objects already in the graph are matched, as uncertain.
    static func blockReferences(of block: AnyObject, into collector: inout ReferenceCollector) {
        // Block_layout: isa(8) flags(4) reserved(4) invoke(8) descriptor(8), then the captures.
        let pointer = UnsafeRawPointer(Unmanaged.passUnretained(block).toOpaque())
        let flags = pointer.load(fromByteOffset: 8, as: UInt32.self)
        guard flags & (1 << 28) == 0,   // BLOCK_IS_GLOBAL: captures nothing
              let descriptor = pointer.load(fromByteOffset: 24, as: UnsafeRawPointer?.self) else { return }
        // Block_descriptor: reserved(8) size(8), copy and dispose if BLOCK_HAS_COPY_DISPOSE, then
        // signature and layout if BLOCK_HAS_SIGNATURE.
        let size = Int(descriptor.load(fromByteOffset: 8, as: UInt.self))
        var field = 16
        if flags & (1 << 25) != 0 { field += 16 }
        guard flags & (1 << 30) != 0, flags & (1 << 31) != 0 else {
            if isSwiftMade(pointer, flags: flags, size: size, collector: collector) {
                collector.closure(function: pointer.load(fromByteOffset: 32, as: UInt.self),
                                  context: pointer.load(fromByteOffset: 40, as: UInt.self),
                                  at: RetainPath([.field("closure")]), certain: true, keepAlive: block)
                return
            }
            collector.scanForKnownObjects(pointer, from: 32, size: size, keepAlive: block)
            return
        }
        let layout = descriptor.load(fromByteOffset: field + 8, as: UInt.self)
        var strongOffsets: [Int] = []
        var byrefOffsets: [Int] = []
        var offset = 32
        if layout < 0x1000 {
            // Inline: 0xXYZ = X strong, then Y byref, then Z weak captures.
            let strong = Int((layout >> 8) & 0xF), byref = Int((layout >> 4) & 0xF)
            strongOffsets = (0..<strong).map { offset + 8 * $0 }
            byrefOffsets = (0..<byref).map { offset + 8 * (strong + $0) }
        } else if let bytes = UnsafePointer<UInt8>(bitPattern: layout) {
            var cursor = bytes
            scan: while cursor.pointee != 0 {
                let count = Int(cursor.pointee & 0xF) + 1
                switch cursor.pointee >> 4 {
                case 1: offset += count                                   // non-object bytes
                case 3: strongOffsets += (0..<count).map { offset + 8 * $0 }; offset += 8 * count
                case 4: byrefOffsets += (0..<count).map { offset + 8 * $0 }; offset += 8 * count
                case 2, 5, 6: offset += 8 * count                         // words, weak, unretained
                default: break scan
                }
                cursor += 1
            }
        }
        for (index, captureOffset) in strongOffsets.enumerated() where captureOffset + 8 <= size {
            if let address = UnsafeRawPointer(bitPattern: pointer.load(fromByteOffset: captureOffset, as: UInt.self)),
               case .object(let object) = HeapPointer(address) {
                collector.add(RetainPath([.capture(index)]), .object(object))
            }
        }
        for (index, captureOffset) in byrefOffsets.enumerated() where captureOffset + 8 <= size {
            if let object = byrefObject(pointer.load(fromByteOffset: captureOffset, as: UInt.self)) {
                collector.add(RetainPath([.capture(strongOffsets.count + index), .field("__block")]), .object(object))
            }
        }
    }

    /// A block made by Swift from a closure stores just that closure: a function pointer, then its context,
    /// which the copy helper retains. Known by its invoke symbol in the app's images; elsewhere (a block a
    /// framework's Swift code made) by its shape: no clang layout, a code pointer, then nothing, an object
    /// already in the graph, or a valid closure context. A clang block of that shape, built without ARC,
    /// retains that word too.
    private static func isSwiftMade(_ block: UnsafeRawPointer, flags: UInt32, size: Int, collector: ReferenceCollector) -> Bool {
        guard size == 48, flags & (1 << 25) != 0 else { return false }    // BLOCK_HAS_COPY_DISPOSE
        if SymbolNames.isSwiftBlockThunk(at: block.load(fromByteOffset: 16, as: UInt.self)) { return true }
        let function = block.load(fromByteOffset: 32, as: UInt.self), context = block.load(fromByteOffset: 40, as: UInt.self)
        guard SymbolNames.isInLoadedImage(function) else { return false }
        return context == 0 || collector.known(context) != nil || HeapPointer.closureContext(at: context) != nil
    }

    /// The object in a `__block` variable whose byref layout says it is strong.
    private static func byrefObject(_ address: UInt) -> AnyObject? {
        // Block_byref: isa(8) forwarding(8) flags(4) size(4), keep and destroy if BLOCK_BYREF_HAS_COPY_DISPOSE,
        // the layout if BLOCK_BYREF_LAYOUT_EXTENDED, then the variable. Copied to the heap with the block.
        guard let byref = UnsafeRawPointer(bitPattern: address), malloc_size(byref) >= 32,
              byref.load(fromByteOffset: 8, as: UInt.self) == address else { return nil }
        let flags = byref.load(fromByteOffset: 16, as: UInt32.self)
        let layout = flags & (0xF << 28)
        guard layout == 3 << 28 else { return nil }    // BLOCK_BYREF_LAYOUT_STRONG
        let variable = 24 + (flags & (1 << 25) != 0 ? 16 : 0)
        guard variable + 8 <= malloc_size(byref),
              let object = UnsafeRawPointer(bitPattern: byref.load(fromByteOffset: variable, as: UInt.self)),
              case .object(let value) = HeapPointer(object) else { return nil }
        return value
    }
}

private final class IvarCache: @unchecked Sendable {
    static let shared = IvarCache()
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: [(name: String, ivar: Ivar)]] = [:]

    func ivars(of cls: AnyClass, read: () -> [(name: String, ivar: Ivar)]) -> [(name: String, ivar: Ivar)] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[ObjectIdentifier(cls)] { return cached }
        let ivars = read()
        entries[ObjectIdentifier(cls)] = ivars
        return ivars
    }
}

#endif
