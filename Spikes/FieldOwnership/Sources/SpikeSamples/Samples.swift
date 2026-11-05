//
//  Samples.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — sample types. Every type has strong, weak and unowned fields.
//  Field types are chosen so mangled names cover:
//    - same-module Swift class  → direct symbolic reference   (Target)
//    - other-module Swift class → indirect symbolic reference (ExternalTarget)
//    - ObjC class               → plain "So…C" name           (NSObject, UIView)
//    - class-bound protocols, AnyObject, generic parameters
//

import Foundation
import SpikeExternal
#if canImport(UIKit)
import UIKit
#endif

public final class Target { public init() {} }
public protocol SwiftDelegate: AnyObject {}
@objc public protocol ObjCDelegate: AnyObject {}

// MARK: Q1/Q2 — kinds of types

public final class PureSwiftClass {
    public var strongRef = Target()
    public weak var weakRef: Target?
    public unowned var unownedRef: Target
    public unowned(unsafe) var unsafeRef: Target
    public weak var weakExternal: ExternalTarget?
    public unowned var unownedExternal: ExternalTarget
    public weak var weakObjC: NSObject?
    public weak var weakSwiftDelegate: SwiftDelegate?
    public weak var weakObjCDelegate: ObjCDelegate?
    public weak var weakAnyObject: AnyObject?
    public let strongLet: ExternalTarget

    public init(_ t: Target, _ e: ExternalTarget) {
        unownedRef = t; unsafeRef = t; unownedExternal = e; strongLet = e
    }
}

public class SwiftBase {
    public var strongBase = Target()
    public weak var weakBase: Target?
    public init() {}
}

public final class SwiftSubclass: SwiftBase {
    public var strongChild = Target()
    public weak var weakChild: Target?
    public unowned var unownedChild: Target
    public init(_ t: Target) { unownedChild = t; super.init() }
}

public final class NSObjectSubclass: NSObject {
    public var strongRef = Target()
    public weak var weakRef: Target?
    public unowned var unownedRef: Target
    @objc public weak var weakObjCProperty: NSObject?
    public init(_ t: Target) { unownedRef = t; super.init() }
}

#if canImport(UIKit)
public final class ViewControllerSubclass: UIViewController {
    public var strongRef = Target()
    public weak var weakView: UIView?
    public weak var weakDelegate: SwiftDelegate?
    public unowned var unownedRef: Target
    public init(_ t: Target) { unownedRef = t; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}
#endif

public struct PlainStruct {
    public var strongRef: Target
    public weak var weakRef: Target?
    public unowned var unownedRef: Target
    public init(_ t: Target) { strongRef = t; weakRef = t; unownedRef = t }
}

public final class GenericClass<T: AnyObject> {
    public var strongRef: T
    public weak var weakRef: T?
    public unowned var unownedRef: T
    public var strongArray: [T] = []
    public init(_ t: T) { strongRef = t; weakRef = t; unownedRef = t }
}

public struct GenericStruct<T: AnyObject, U> {
    public var strongRef: T
    public weak var weakRef: T?
    public unowned var unownedRef: T
    public var payload: U
    public init(_ t: T, _ u: U) { strongRef = t; weakRef = t; unownedRef = t; payload = u }
}

/// Generic subclass of a generic base: fields of both levels.
public class GenericBase<T: AnyObject> {
    public weak var weakBase: T?
    public init() {}
}
public final class GenericSubclass<T: AnyObject>: GenericBase<T> {
    public unowned var unownedChild: T
    public var strongChild: T
    public init(_ t: T) { unownedChild = t; strongChild = t; super.init() }
}

// MARK: Q3 — lazy var and property wrappers

@propertyWrapper
public struct WeakRef<T: AnyObject> {
    public weak var value: T?
    public init(wrappedValue: T?) { value = wrappedValue }
    public var wrappedValue: T? { get { value } set { value = newValue } }
}

@propertyWrapper
public struct Boxed<T> {
    public var value: T
    public init(wrappedValue: T) { value = wrappedValue }
    public var wrappedValue: T { get { value } set { value = newValue } }
}

public final class LazyAndWrappers {
    public lazy var lazyStrong = Target()
    public lazy var lazyOptional: Target? = nil
    @WeakRef public var wrappedWeak: Target?
    @Boxed public var boxedStrong: Target
    public weak var plainWeak: Target?
    public init(_ t: Target) { wrappedWeak = t; boxedStrong = t }
}
