//
//  SymbolRebinder.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import MachO

/// Points an image's calls to an external C function at a replacement, by rewriting its lazy and
/// non-lazy symbol pointers (what fishhook does). Only calls made through that image's stubs change.
package enum SymbolRebinder {
    private static let indirectSymbolLocal: UInt32 = 0x8000_0000
    private static let indirectSymbolAbsolute: UInt32 = 0x4000_0000

    /// Returns how many pointers were rewritten.
    @discardableResult
    package static func rebind(_ symbol: String, to replacement: UnsafeRawPointer, in header: UnsafePointer<mach_header>, slide: Int) -> Int {
        let base = UnsafeRawPointer(header)
        guard header.pointee.magic == MH_MAGIC_64 else { return 0 }
        let commandCount = Int(header.pointee.ncmds)

        var linkedit: segment_command_64?
        var symtab: symtab_command?
        var dysymtab: dysymtab_command?
        var dataSegments: [UnsafeRawPointer] = []
        var cursor = base + MemoryLayout<mach_header_64>.size
        for _ in 0..<commandCount {
            let command = cursor.load(as: load_command.self)
            switch command.cmd {
            case UInt32(LC_SEGMENT_64):
                let segment = cursor.load(as: segment_command_64.self)
                let name = segmentName(segment)
                if name == SEG_LINKEDIT { linkedit = segment }
                if name.hasPrefix("__DATA") || name.hasPrefix("__AUTH") { dataSegments.append(cursor) }
            case UInt32(LC_SYMTAB):
                symtab = cursor.load(as: symtab_command.self)
            case UInt32(LC_DYSYMTAB):
                dysymtab = cursor.load(as: dysymtab_command.self)
            default:
                break
            }
            cursor += Int(command.cmdsize)
        }
        guard let linkedit, let symtab, let dysymtab, dysymtab.nindirectsyms > 0 else { return 0 }

        let linkeditBase = UInt(bitPattern: slide) &+ UInt(linkedit.vmaddr) &- UInt(linkedit.fileoff)
        guard let symbols = UnsafePointer<nlist_64>(bitPattern: linkeditBase &+ UInt(symtab.symoff)),
              let strings = UnsafePointer<CChar>(bitPattern: linkeditBase &+ UInt(symtab.stroff)),
              let indirect = UnsafePointer<UInt32>(bitPattern: linkeditBase &+ UInt(dysymtab.indirectsymoff)) else { return 0 }

        let target = "_" + symbol
        var rewritten = 0
        for segmentPointer in dataSegments {
            let segment = segmentPointer.load(as: segment_command_64.self)
            // dyld makes these read-only after binding, whatever the load command says.
            let isReadOnly = ["__DATA_CONST", "__AUTH_CONST"].contains(segmentName(segment))
            var sectionPointer = segmentPointer + MemoryLayout<segment_command_64>.size
            for _ in 0..<Int(segment.nsects) {
                let section = sectionPointer.load(as: section_64.self)
                sectionPointer += MemoryLayout<section_64>.size
                let type = section.flags & UInt32(SECTION_TYPE)
                guard type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS,
                      let slots = UnsafeMutablePointer<UnsafeRawPointer?>(bitPattern: UInt(section.addr) &+ UInt(bitPattern: slide))
                else { continue }
                for index in 0..<Int(section.size) / MemoryLayout<UnsafeRawPointer>.size {
                    let symbolIndex = indirect[Int(section.reserved1) + index]
                    guard symbolIndex & (indirectSymbolLocal | indirectSymbolAbsolute) == 0 else { continue }
                    let nameOffset = Int(symbols[Int(symbolIndex)].n_un.n_strx)
                    guard strcmp(strings + nameOffset, target) == 0 else { continue }
                    if write(replacement, to: slots + index, readOnly: isReadOnly) { rewritten += 1 }
                }
            }
        }
        return rewritten
    }

    private static func write(_ value: UnsafeRawPointer, to slot: UnsafeMutablePointer<UnsafeRawPointer?>, readOnly: Bool) -> Bool {
        guard readOnly else {
            slot.pointee = value
            return true
        }
        let address = vm_address_t(UInt(bitPattern: slot))
        let size = vm_size_t(MemoryLayout<UnsafeRawPointer>.size)
        guard vm_protect(mach_task_self_, address, size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) == KERN_SUCCESS
        else { return false }
        slot.pointee = value
        vm_protect(mach_task_self_, address, size, 0, VM_PROT_READ)
        return true
    }

    private static func segmentName(_ segment: segment_command_64) -> String {
        withUnsafeBytes(of: segment.segname) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

#endif
