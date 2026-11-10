//
//  SymbolNames.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import MachO

/// Readable names for code and static data addresses, from the symbol table. Debug builds keep symbols.
package enum SymbolNames {
    private typealias Demangle = @convention(c) (
        UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
    ) -> UnsafeMutablePointer<CChar>?

    // Looked up at run time: declaring it with @_silgen_name is reserved for the Swift runtime.
    private static let demangle: Demangle? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle")
        .map { unsafeBitCast($0, to: Demangle.self) }

    private static let cache = Cache()

    /// `closure #1 in ProfileVC.viewDidLoad()`, `ProfileVC.refresh()` for a method reference, `closure` otherwise.
    package static func closure(at function: UInt) -> String {
        cache.value(for: function) {
            // Looking up a symbol in a system framework can take milliseconds: those are named by image.
            if let image = AppImages.shared.imageOutsideApp(containing: function) { return "closure in \(image)" }
            guard let symbol = demangledSymbol(at: function) else { return "closure" }
            // What Swift wraps a closure in to pass it where another signature is expected: it holds the closure.
            if symbol.contains("reabstraction thunk") { return "reabstraction thunk" }
            // A private function demangles as `(helper in _9664DA07…)`.
            var text = symbol.replacingOccurrences(of: #"\((\w+) in _[0-9A-F]+\)"#, with: "$1", options: .regularExpression)
            for prefix in ["async function pointer to ", "partial apply forwarder for ", "partial apply for ", "thunk for ",
                           "reabstraction thunk helper from "]
            where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
            let closure = text.range(of: #"^closure #\d+"#, options: .regularExpression).map { String(text[$0]) }
            let owner = (text.range(of: " in ", options: .backwards).map { String(text[$0.upperBound...]) } ?? text)
            let function = shortFunctionName(owner)
            return closure.map { "\($0) in \(function)" } ?? function
        }
    }

    /// `true` for the invoke function Swift emits when it turns a closure into a block. Only symbols of the
    /// app's own images are looked up: elsewhere a lookup can take milliseconds, and the answer stays `false`.
    static func isSwiftBlockThunk(at invoke: UInt) -> Bool {
        thunks.value(for: invoke) {
            guard AppImages.shared.imageOutsideApp(containing: invoke) == nil, let symbol = demangledSymbol(at: invoke) else { return "" }
            return symbol.hasPrefix("reabstraction thunk") && symbol.contains("@convention(block)") ? "yes" : ""
        } == "yes"
    }

    private static let thunks = Cache()

    /// A static variable used as an associated object key: `helperKey`, or its address.
    static func variable(at address: UInt) -> String {
        cache.value(for: address) {
            guard AppImages.shared.imageOutsideApp(containing: address) == nil, let symbol = demangledSymbol(at: address)
            else { return "0x" + String(address, radix: 16) }
            var name = symbol.components(separatedBy: " : ").first ?? symbol
            // A private variable demangles as `(helperKey in _871D9558…)`.
            if let range = name.range(of: #"\((\w+) in _[0-9A-F]+\)"#, options: .regularExpression) {
                name = String(name[range].dropFirst().prefix { $0 != " " })
            }
            return name.components(separatedBy: ".").last ?? name
        }
    }

    private static func demangledSymbol(at address: UInt) -> String? {
        var info = Dl_info()
        guard let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0,
              let raw = info.dli_sname else { return nil }
        let mangled = String(cString: raw)
        guard let demangle, let output = demangle(raw, strlen(raw), nil, nil, 0) else { return mangled }
        defer { free(output) }
        return String(cString: output)
    }

    /// `MyApp.ProfileVC.viewDidLoad() async throws -> ()` → `ProfileVC.viewDidLoad()`.
    private static func shortFunctionName(_ text: String) -> String {
        var name = text.components(separatedBy: " -> ").first ?? text
        for effect in [" throws", " async"] where name.hasSuffix(effect) {
            name.removeLast(effect.count)
        }
        if let open = name.firstIndex(of: "("), let lastDot = name[..<open].lastIndex(of: "."),
           let typeDot = name[..<lastDot].lastIndex(of: ".") {
            name = String(name[name.index(after: typeDot)...])
        }
        return name
    }

    /// `true` when `address` is inside a loaded image: a range lookup, cheap enough for a scanning loop.
    static func isInLoadedImage(_ address: UInt) -> Bool {
        AppImages.shared.contains(address)
    }

    /// `true` for code or data of the app's own images: anything that is not a system image.
    package static func isAppCode(_ address: UInt) -> Bool {
        AppImages.shared.contains(address) && AppImages.shared.imageOutsideApp(containing: address) == nil
    }

    /// `true` for classes defined by the app's own images. Decided by where the class lives, like images
    /// are: on a simulator the path `class_getImageName` reports is not one the shared cache answers for.
    package static func isAppClass(_ cls: AnyClass) -> Bool {
        let metadata = unsafeBitCast(cls, to: UnsafeRawPointer.self)
        // An Objective-C class reaches Swift wrapped (kind 0x305): the class itself is the next word.
        let address = SwiftMetadata.isClass(metadata) ? UInt(bitPattern: metadata) : metadata.load(fromByteOffset: 8, as: UInt.self)
        if AppImages.shared.contains(address) { return AppImages.shared.imageOutsideApp(containing: address) == nil }
        // Generic class metadata is made at run time, outside any image.
        guard let path = class_getImageName(cls) else { return false }
        return !AppImages.isSystem(String(cString: path), path)
    }

    /// Address ranges of loaded images. System images are the ones in the dyld shared cache. Read again
    /// when an address is in none of them and more images have been loaded since: a test bundle, a plug-in.
    private final class AppImages: @unchecked Sendable {
        typealias Image = (range: Range<UInt>, name: String, isApp: Bool)

        static let shared = AppImages()
        private let lock = NSLock()
        private var images: [Image] = []
        private var count: UInt32 = 0

        private init() {
            reload()
        }

        private func reload() {
            let total = _dyld_image_count()
            var images: [Image] = []
            for index in 0..<total {
                guard let header = _dyld_get_image_header(index), let rawPath = _dyld_get_image_name(index) else { continue }
                let path = String(cString: rawPath)
                let slide = UInt(bitPattern: _dyld_get_image_vmaddr_slide(index))
                let name = path.split(separator: "/").last.map(String.init) ?? path
                let isApp = !Self.isSystem(path, rawPath)
                var command = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
                for _ in 0..<header.pointee.ncmds {
                    let load = command.load(as: load_command.self)
                    if load.cmd == UInt32(LC_SEGMENT_64) {
                        let segment = command.load(as: segment_command_64.self)
                        if segment.vmsize > 0, segment.filesize > 0 || segment.initprot != 0 {
                            let start = UInt(segment.vmaddr) &+ slide
                            images.append((start..<(start + UInt(segment.vmsize)), name, isApp))
                        }
                    }
                    command += Int(load.cmdsize)
                }
            }
            lock.lock()
            self.images = images
            count = total
            lock.unlock()
        }

        private func image(containing address: UInt) -> Image? {
            lock.lock()
            let found = images.first { $0.range.contains(address) }
            let stale = count != _dyld_image_count()
            lock.unlock()
            guard found == nil, stale else { return found }
            reload()
            lock.lock()
            defer { lock.unlock() }
            return images.first { $0.range.contains(address) }
        }

        func contains(_ address: UInt) -> Bool {
            image(containing: address) != nil
        }

        /// In the dyld shared cache, or where system images live: a simulator's test runner loads them
        /// outside any cache.
        static func isSystem(_ path: String, _ rawPath: UnsafePointer<CChar>) -> Bool {
            _dyld_shared_cache_contains_path(rawPath) || path.contains("/RuntimeRoot/")
                || path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/")
        }

        func imageOutsideApp(containing address: UInt) -> String? {
            guard let image = image(containing: address), !image.isApp else { return nil }
            return image.name
        }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [UInt: String] = [:]

        func value(for key: UInt, make: () -> String) -> String {
            lock.lock()
            if let name = names[key] { lock.unlock(); return name }
            lock.unlock()
            let name = make()
            lock.lock()
            names[key] = name
            lock.unlock()
            return name
        }
    }
}

#endif
