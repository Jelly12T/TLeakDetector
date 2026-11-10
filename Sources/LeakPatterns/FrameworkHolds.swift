//
//  FrameworkHolds.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import ObjectiveC
import LeakCore
import LeakGraph
import LeakHeap

/// What system objects hold where no ivar shows it: a timer its target or block, a display link its target,
/// a NotificationCenter observer its block, a URLSession its delegate, a WKUserContentController its script
/// message handlers. Seen by hooking the methods that create them; everything is held weakly.
///
/// Only holds whose target, delegate, handler or block belongs to the app are recorded: system frameworks
/// make many of these for themselves.
package final class FrameworkHolds: @unchecked Sendable {
    package static let shared = FrameworkHolds()

    enum Kind {
        case timerTarget, timerBlock, displayLink, observer, urlSession, scriptMessageHandler
    }

    final class Hold: @unchecked Sendable {
        let kind: Kind
        weak var holder: AnyObject?
        weak var referent: AnyObject?
        /// A notification or handler name.
        let name: String
        var isRemoved = false

        init(_ kind: Kind, holder: AnyObject, referent: AnyObject, name: String = "") {
            self.kind = kind
            self.holder = holder
            self.referent = referent
            self.name = name
        }

        var path: RetainPath {
            switch kind {
            case .timerTarget, .displayLink: RetainPath([.field("target")])
            case .timerBlock, .observer: RetainPath([.field("block")])
            case .urlSession: RetainPath([.field("delegate")])
            case .scriptMessageHandler: RetainPath([.field("scriptMessageHandlers"), .value(key: "\"\(name)\"")])
            }
        }

        /// Still holding: a valid timer, a link not invalidated, an observer or handler not removed, a session
        /// not invalidated (an invalidated session lets its delegate go).
        var isActive: Bool {
            guard let holder, !isRemoved else { return false }
            switch kind {
            case .timerTarget, .timerBlock: return (holder as? Timer)?.isValid ?? false
            case .urlSession: return (holder as? URLSession)?.delegate != nil
            case .displayLink, .observer, .scriptMessageHandler: return true
            }
        }

        /// The system keeps the holder itself alive: a root of what holds a leaked object.
        var holderKind: LeakHolder? {
            switch kind {
            case .timerTarget, .timerBlock:
                guard let timer = holder as? Timer else { return nil }
                return LeakHolder(.timer, detail: timer.timeInterval > 0 ? "repeats every \(timer.timeInterval)s" : "")
            case .displayLink: return LeakHolder(.displayLink)
            case .observer: return LeakHolder(.notificationObserver, detail: name.isEmpty ? "every notification" : name)
            case .urlSession: return LeakHolder(.urlSession)
            case .scriptMessageHandler: return nil
            }
        }
    }

    private let lock = NSLock()
    private var holds: [ObjectIdentifier: [Hold]] = [:]
    private var added = 0
    private(set) var isInstalled = false

    /// Hooks every creating method once. `isApp` tells whether a target, delegate or block is the app's.
    package func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !isInstalled else { return }
        isInstalled = true
        FrameworkHooks.install(into: self)
    }

    func record(_ hold: Hold) {
        guard let holder = hold.holder, let referent = hold.referent, Self.isApp(referent) else { return }
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(holder)
        var list = (holds[key] ?? []).filter { $0.holder === holder && !($0.kind == hold.kind && $0.name == hold.name) }
        list.append(hold)
        holds[key] = list
        added += 1
        if added % 128 == 0 { holds = holds.filter { !$0.value.allSatisfy { $0.holder == nil } } }
    }

    /// Marks the holds of `holder` matching `matches` as removed: an observer or handler unregistered, a link invalidated.
    func remove(holder: AnyObject, where matches: (Hold) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        for hold in holds[ObjectIdentifier(holder)] ?? [] where hold.holder === holder && matches(hold) {
            hold.isRemoved = true
        }
    }

    private func holds(of holder: AnyObject) -> [Hold] {
        lock.lock()
        defer { lock.unlock() }
        return (holds[ObjectIdentifier(holder)] ?? []).filter { $0.holder === holder }
    }

    var all: [Hold] {
        lock.lock()
        defer { lock.unlock() }
        return holds.values.flatMap { $0 }.filter { $0.holder != nil }
    }

    /// Strong references `object` keeps through system storage, for the retain graph.
    package func references(of object: AnyObject) -> [(path: RetainPath, target: AnyObject)] {
        var found = holds(of: object).compactMap { hold in
            hold.isActive ? hold.referent.map { (hold.path, $0) } : nil
        }
        if let controller = Self.userContentController(of: object) {
            found.append((RetainPath([.field("configuration"), .field("userContentController")]), controller))
        }
        return found
    }

    /// Active holders the system itself keeps alive: where a search for what holds a leaked object starts.
    package func roots() -> [(holder: LeakHolder, object: AnyObject)] {
        all.compactMap { hold in
            guard hold.isActive, let kind = hold.holderKind, let holder = hold.holder else { return nil }
            return (kind, holder)
        }
    }

    /// A target, delegate or handler from the app, or a block whose code is the app's.
    static func isApp(_ object: AnyObject) -> Bool {
        let cls: AnyClass = type(of: object)
        if ObjCClasses.isBlock(cls) {
            let invoke = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque()).load(fromByteOffset: 16, as: UInt.self)
            return SymbolNames.isAppCode(invoke)
        }
        return SymbolNames.isAppClass(cls)
    }

    /// A web view holds its content controller through WebKit's own storage.
    private static func userContentController(of object: AnyObject) -> AnyObject? {
        guard let webView = ObjCClasses.webView, inherits(type(of: object), from: webView),
              let configuration = (object as? NSObject)?.value(forKey: "configuration") as? NSObject else { return nil }
        return configuration.value(forKey: "userContentController") as AnyObject?
    }
}

enum ObjCClasses {
    static let block: AnyClass? = NSClassFromString("NSBlock")
    static let webView: AnyClass? = NSClassFromString("WKWebView")
    static let userContentController: AnyClass? = NSClassFromString("WKUserContentController")
    static let displayLink: AnyClass? = NSClassFromString("CADisplayLink")

    static func isBlock(_ cls: AnyClass) -> Bool {
        block.map { inherits(cls, from: $0) } ?? false
    }
}

/// Read from the class chain: messaging a proxy forwards the message.
func inherits(_ cls: AnyClass, from base: AnyClass) -> Bool {
    var current: AnyClass? = cls
    while let candidate = current {
        if candidate === base { return true }
        current = class_getSuperclass(candidate)
    }
    return false
}

#endif
