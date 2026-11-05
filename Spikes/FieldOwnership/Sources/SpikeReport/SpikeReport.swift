//
//  SpikeReport.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — prints one `SPIKE|…` line per finding; scripts/ collect them into results/.
//  Shared by the test target (simulator) and SpikeHost app (device: package tests
//  cannot run tool-hosted on a device).
//

import Foundation
import FieldOwnershipReader
import SpikeExternal
import SpikeSamples
#if canImport(UIKit)
import UIKit
#endif

private struct Case {
    let label: String
    let question: String           // which question it mainly answers
    let instance: Any
    let expected: [(String, Ownership)]   // own fields first, then superclass fields
}

private func makeCases() -> [Case] {
    let t = Target(), e = ExternalTarget()
    var cases: [Case] = [
        Case(label: "PureSwiftClass", question: "Q1 Q2", instance: PureSwiftClass(t, e), expected: [
            ("strongRef", .strong), ("weakRef", .weak), ("unownedRef", .unowned), ("unsafeRef", .unownedUnsafe),
            ("weakExternal", .weak), ("unownedExternal", .unowned), ("weakObjC", .weak),
            ("weakSwiftDelegate", .weak), ("weakObjCDelegate", .weak), ("weakAnyObject", .weak), ("strongLet", .strong)]),
        Case(label: "SwiftSubclass", question: "Q1", instance: SwiftSubclass(t), expected: [
            ("strongChild", .strong), ("weakChild", .weak), ("unownedChild", .unowned),
            ("strongBase", .strong), ("weakBase", .weak)]),
        Case(label: "NSObjectSubclass", question: "Q1", instance: NSObjectSubclass(t), expected: [
            ("strongRef", .strong), ("weakRef", .weak), ("unownedRef", .unowned), ("weakObjCProperty", .weak)]),
        Case(label: "PlainStruct", question: "Q1", instance: PlainStruct(t), expected: [
            ("strongRef", .strong), ("weakRef", .weak), ("unownedRef", .unowned)]),
        Case(label: "GenericClass<Target>", question: "Q1 Q2", instance: GenericClass(t), expected: [
            ("strongRef", .strong), ("weakRef", .weak), ("unownedRef", .unowned), ("strongArray", .strong)]),
        Case(label: "GenericStruct<ExternalTarget,Int>", question: "Q1 Q2", instance: GenericStruct(e, 1), expected: [
            ("strongRef", .strong), ("weakRef", .weak), ("unownedRef", .unowned), ("payload", .strong)]),
        Case(label: "GenericSubclass<Target>", question: "Q1", instance: GenericSubclass(t), expected: [
            ("unownedChild", .unowned), ("strongChild", .strong), ("weakBase", .weak)]),
        Case(label: "LazyAndWrappers", question: "Q3", instance: LazyAndWrappers(t), expected: [
            ("$__lazy_storage_$_lazyStrong", .strong), ("$__lazy_storage_$_lazyOptional", .strong),
            ("_wrappedWeak", .strong), ("_boxedStrong", .strong), ("plainWeak", .weak)]),
    ]
    #if canImport(UIKit)
    cases.insert(Case(label: "ViewControllerSubclass", question: "Q1 Q2", instance: ViewControllerSubclass(t), expected: [
        ("strongRef", .strong), ("weakView", .weak), ("weakDelegate", .weak), ("unownedRef", .unowned)]), at: 3)
    #endif
    return cases
}

/// Mirror labels in the reader's order: own fields, then each superclass.
private func mirrorLabels(_ value: Any) -> [String] {
    var labels: [String] = []
    var mirror: Mirror? = Mirror(reflecting: value)
    while let m = mirror {
        labels += m.children.map { $0.label ?? "<nil>" }
        mirror = m.superclassMirror
    }
    return labels
}

private func environment() -> String {
    #if targetEnvironment(simulator)
    let where_ = "simulator"
    #else
    let where_ = "device"
    #endif
    #if canImport(UIKit)
    let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) \(UIDevice.current.model)"
    #else
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    #endif
    #if arch(arm64)
    let arch = "arm64"
    #else
    let arch = "x86_64"
    #endif
    return "\(where_)|\(os)|\(arch)"
}

private func emit(_ parts: Any...) {
    print((["SPIKE"] + parts.map { "\($0)" }).joined(separator: "|"))
}

public enum SpikeReport {
    /// Prints the report and returns the ids of failed checks (empty = all matched).
    @discardableResult
    public static func run() -> [String] {
        var failures: [String] = []

        emit("ENV", environment())
        var tally = ["Q1": (0, 0), "Q2": (0, 0), "Q3": (0, 0)]
        func count(_ q: String, _ ok: Bool) {
            tally[q] = (tally[q]!.0 + (ok ? 1 : 0), tally[q]!.1 + 1)
            if !ok { failures.append(q) }
        }

        for c in makeCases() {
            let result = FieldOwnershipReader.read(c.instance)
            let labels = mirrorLabels(c.instance)
            let runtime = RuntimeFieldReader.fields(of: type(of: c.instance))
            let runtimeByName = Dictionary(runtime.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

            // Q1: did we reach the field descriptor(s) and get every field?
            let reached = result.failure == nil && result.fields.count == c.expected.count
            count("Q1", reached)
            emit("TYPE", c.label, "path=" + result.path.joined(separator: " → "),
                 "failure=\(result.failure ?? "-")", "fields=\(result.fields.count)/\(c.expected.count)",
                 "mirrorLabels=\(labels.count)", "runtimeFields=\(runtime.count)")

            for (index, expected) in c.expected.enumerated() {
                let field = index < result.fields.count ? result.fields[index] : nil
                let label = index < labels.count ? labels[index] : "<none>"
                let ownership = field?.ownership.rawValue ?? "<unread>"
                // Q2: ownership from the mangled suffix.
                let ownershipOK = field?.ownership == expected.1
                count("Q2", ownershipOK)
                // Q3: descriptor name == expected name == Mirror label.
                let nameOK = field?.name == expected.0 && label == expected.0
                count("Q3", nameOK)
                let rt = runtimeByName[expected.0].map { $0.isStrong ? "strong" : "notStrong" } ?? "n/a"
                emit("FIELD", c.label, index, field?.declaringType ?? "-", field?.name ?? "<unread>", label,
                     field?.mangledTypeName ?? "-", field?.hasSymbolicReference == true ? "sym" : "plain",
                     ownership, "runtime=\(rt)", "expected=\(expected.0):\(expected.1.rawValue)",
                     ownershipOK && nameOK ? "OK" : "FAIL")
            }

            // Fallback probe: what the ObjC runtime alone sees for this class.
            if let cls = type(of: c.instance) as? AnyClass {
                var n: UInt32 = 0
                let ivars = class_copyIvarList(cls, &n)
                let names = (0..<Int(n)).map { ivar_getName(ivars![$0]).map { String(cString: $0) } ?? "?" }
                free(ivars)
                emit("OBJC", c.label, "ivars=\(n)", names.joined(separator: ","),
                     "weakIvarLayout=\(class_getWeakIvarLayout(cls) == nil ? "nil" : "present")",
                     "strongIvarLayout=\(class_getIvarLayout(cls) == nil ? "nil" : "present")")
            }

            // Q3 extra: a property wrapper hides the ownership one level down.
            if c.label == "LazyAndWrappers", let wrapper = runtime.first(where: { $0.name == "_wrappedWeak" }) {
                let inner = FieldOwnershipReader.read(type: wrapper.type)
                for f in inner.fields {
                    emit("NESTED", c.label, "_wrappedWeak: \(wrapper.type)", f.name, f.mangledTypeName, f.ownership.rawValue)
                }
            }
        }
        for q in ["Q1", "Q2", "Q3"] {
            emit("SUMMARY", q, "\(tally[q]!.0)/\(tally[q]!.1)")
        }
        return failures
    }
}
