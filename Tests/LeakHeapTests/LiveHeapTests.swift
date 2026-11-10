//
//  LiveHeapTests.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import Testing
import LeakGraph
import LeakHeapFixtures
@testable import LeakHeap

struct Found {
    let path: String
    let target: LiveHeap.Object
    let kind: RetainGraph.Node.Kind
    let certain: Bool

    var object: AnyObject? {
        if case .object(let object) = target { return object }
        return nil
    }
}

/// References of `object`, read by a heap that has already seen `object` (and `alsoSeen`).
func references(of object: LiveHeap.Object, alsoSeen: [AnyObject] = [], heap: LiveHeap = LiveHeap()) -> [Found] {
    _ = heap.node(for: object)
    for other in alsoSeen { _ = heap.node(for: .object(other)) }
    return heap.strongReferences(from: object).map {
        Found(path: $0.path.description, target: $0.target, kind: heap.node(for: $0.target).kind, certain: $0.isCertain)
    }
}

func references(of object: AnyObject) -> [Found] {
    references(of: .object(object))
}

func cycle(through object: AnyObject) -> RetainChain? {
    LiveHeap().shortestCycle(through: .object(object)).cycle
}

// MARK: - Swift

final class Child {}
final class Owner {}

final class StoredFields {
    var strong: Child? = Child()
    weak var weakChild: Child?
    unowned let owner: Owner
    unowned(unsafe) let unsafeOwner: Owner
    var number = 3
    lazy var lazyChild = Child()

    init(owner: Owner) {
        self.owner = owner
        self.unsafeOwner = owner
    }
}

struct Pair {
    var child: Child
    weak var weakChild: Child?
}

@propertyWrapper
struct WeakRef<Value: AnyObject> {
    private weak var value: Value?

    init(wrappedValue: Value?) {
        value = wrappedValue
    }

    var wrappedValue: Value? {
        get { value }
        set { value = newValue }
    }
}

enum LoadState {
    case idle
    case loaded(Child)
}

final class Containers {
    var array = [Child(), Child()]
    var dictionary = ["a": Child()]
    var tuple = (Child(), 1)
    var state = LoadState.loaded(Child())
    var pair = Pair(child: Child(), weakChild: nil)
    @WeakRef<Child> var wrapped: Child? = nil
    var optional: Child?? = Child()
}

final class Screen {
    var onRefresh: (() -> Void)?
    var handler: (() -> Void)?
    var delegate: AnyObject?
    func refresh() {}
}

@Suite("Swift provider")
struct SwiftProviderTests {
    @Test("Strong stored properties are followed; weak, unowned and unowned(unsafe) ones are never read")
    func storedProperties() {
        let kept = Child()
        var fields: StoredFields!
        do {
            let owner = Owner()
            fields = StoredFields(owner: owner)
            fields.weakChild = kept
            _ = fields.lazyChild
        }
        // The owner is gone: reading `owner` would trap, reading `unsafeOwner` would dangle.
        let found = references(of: fields)
        #expect(found.map(\.path) == ["strong", "lazyChild"])
        #expect(found.allSatisfy { $0.certain })
        withExtendedLifetime(kept) {}
    }

    @Test("Values are walked: arrays, dictionaries, tuples, enum payloads, structs, optionals; weak inside structs and wrappers skipped")
    func containers() {
        let containers = Containers()
        let weakTarget = Child()
        containers.wrapped = weakTarget
        containers.pair.weakChild = weakTarget
        let found = references(of: containers)
        #expect(found.map(\.path) == [
            "array[0]", "array[1]", #"dictionary["a"]"#, "tuple.0", "state.loaded", "pair.child", "optional",
        ])
        #expect(!found.contains { $0.object === weakTarget })
    }

    @Test("A closure capturing only self uses self as its context: a certain reference through the closure")
    func closureCapturingOnlySelf() throws {
        let screen = Screen()
        screen.onRefresh = { screen.refresh() }
        defer { screen.onRefresh = nil }

        let found = try #require(references(of: screen).first)
        #expect(found.object === screen)
        #expect(found.certain)
        #expect(found.path.hasPrefix("onRefresh {closure #1 in SwiftProviderTests.closureCapturingOnlySelf()"))
        #expect(cycle(through: screen)?.isCertain == true)
    }

    @Test("A closure capturing several values has a context node; its captures are read from metadata")
    func closureContext() throws {
        let screen = Screen(), helper = Child()
        screen.handler = { screen.refresh(); _ = helper }
        defer { screen.handler = nil }

        let field = try #require(references(of: screen).first)
        #expect(field.path == "handler")
        guard case .closure(let function) = field.kind else { Issue.record("not a closure: \(field.kind)"); return }
        #expect(function.hasPrefix("closure #1 in SwiftProviderTests.closureContext()"))

        let captures = references(of: field.target)
        #expect(captures.map(\.path) == ["capture 0", "capture 1"])
        #expect(captures[0].object === screen && captures[1].object === helper)
        #expect(captures.allSatisfy { $0.certain })

        let found = try #require(cycle(through: screen))
        #expect(found.isCertain)
        #expect(found.description.hasPrefix("Screen.handler → closure #1 in SwiftProviderTests.closureContext()"))
        #expect(found.description.hasSuffix(".capture 0 → Screen"))
    }

    @Test("[weak self] is skipped; a captured var is a box holding its value")
    func weakAndVarCaptures() throws {
        let screen = Screen(), helper = Child()
        screen.handler = { [weak screen] in screen?.refresh(); _ = helper }
        let weakCaptures = references(of: try #require(references(of: screen).first).target)
        #expect(weakCaptures.contains { $0.object === helper })
        #expect(!weakCaptures.contains { $0.object === screen })
        #expect(cycle(through: screen) == nil)

        var model: Child? = Child()
        screen.handler = { _ = model; screen.refresh() }
        defer { screen.handler = nil }
        let captures = references(of: try #require(references(of: screen).first).target)
        #expect(captures.map(\.path) == ["capture 0", "capture 1"])
        guard case .box = captures[0].kind else { Issue.record("not a box: \(captures[0].kind)"); return }
        #expect(captures[1].object === screen)
        let boxed = references(of: captures[0].target)
        #expect(boxed.map(\.path) == ["value"])
        #expect(boxed.first?.object === model)
        model = nil
    }

    @Test("A closure capturing nothing holds nothing")
    func noCapture() {
        let screen = Screen()
        screen.handler = { print("hi") }
        #expect(references(of: screen).isEmpty)
    }

    @Test("Strong delegate cycle across two objects is certain; the shortest one wins")
    func delegateCycle() throws {
        let screen = Screen(), other = Screen()
        screen.delegate = other
        other.delegate = screen
        defer { other.delegate = nil }
        let found = try #require(cycle(through: screen))
        #expect(found.description == "Screen.delegate → Screen.delegate → Screen")
    }
}

// MARK: - Objective-C

@Suite("Objective-C provider")
struct ObjCProviderTests {
    @Test("Ivars: strong ones from the ARC ivar layout; weak and __unsafe_unretained ones are never read")
    func ivars() {
        let holder = LHFHolder()
        let strong = NSObject(), weak = NSObject(), unretained = NSObject(), property = NSObject()
        holder.setStrong(strong, weak: weak, unretained: unretained)
        holder.strongProperty = property
        holder.weakProperty = weak

        let found = references(of: holder)
        #expect(found.map(\.path) == ["_strongIvar", "_strongProperty"])
        #expect(found.map(\.object) .elementsEqual([strong, property], by: { $0 === $1 }))
        #expect(found.allSatisfy { $0.certain })
        withExtendedLifetime((weak, unretained)) {}
    }

    @Test("A class with only weak ivars has no layout: nothing is read")
    func weakOnly() {
        let object = LHFWeakOnly()
        let target = NSObject()
        object.target = target
        #expect(references(of: .object(object), alsoSeen: [target]).isEmpty)
    }

    @Test("Blocks made by clang: strong captures from the extended layout, weak ones skipped")
    func clangBlocks() throws {
        let holder = LHFHolder(), target = NSObject()
        holder.setBlockCapturingStrongly(target)
        let block = try #require(references(of: holder).first { $0.path == "_block" })
        #expect(block.kind == .block)
        let captures = references(of: block.target)
        #expect(captures.map(\.path) == ["capture 0"])
        #expect(captures.first?.object === target)
        #expect(captures.first?.certain == true)

        holder.setBlockCapturingWeakly(target)
        let weakBlock = try #require(references(of: holder).first { $0.path == "_block" })
        #expect(references(of: weakBlock.target, alsoSeen: [target]).isEmpty)
    }

    @Test("A block made by Swift from a closure holds just that closure: read like one, certain")
    func swiftMadeBlock() throws {
        let holder = LHFHolder()
        holder.callback = { _ = holder }
        defer { holder.callback = nil }
        let found = try #require(cycle(through: holder))
        #expect(found.isCertain)
        #expect(found.description.hasPrefix("LHFHolder._callback → block.closure"))
        #expect(found.description.hasSuffix("→ LHFHolder"))
    }

    @Test("A __block variable is a byref: followed when its layout says strong")
    func byref() throws {
        let holder = LHFHolder(), target = NSObject()
        holder.setBlockCapturingByref(target)
        let block = try #require(references(of: holder).first { $0.path == "_block" })
        let captures = references(of: block.target)
        #expect(captures.map(\.path) == ["capture 0.__block"])
        #expect(captures.first?.object === target)
        #expect(captures.first?.certain == true)
    }

    @Test("Collections: elements, keys and values")
    func collections() {
        let first = NSObject(), second = NSObject()
        let array = references(of: NSArray(array: [first, second]))
        #expect(array.map(\.path) == ["[0]", "[1]"])
        #expect(array.allSatisfy { $0.certain })

        let dictionary = references(of: NSDictionary(dictionary: ["key": first]))
        #expect(dictionary.map(\.path) == ["keys[0]", #"["key"]"#])
        #expect(dictionary.last?.object === first)

        #expect(references(of: NSSet(object: first)).map(\.path) == ["[0]"])
        #expect(references(of: NSOrderedSet(object: first)).map(\.path) == ["[0]"])
    }

    @Test("Hash and map tables follow only what they retain")
    func pointerTables() {
        let first = NSObject(), key = NSString(string: "a long enough key to not be a tagged pointer")
        let weakTable = NSHashTable<AnyObject>.weakObjects()
        weakTable.add(first)
        #expect(references(of: weakTable).isEmpty)

        let strongTable = NSHashTable<AnyObject>(options: .strongMemory)
        strongTable.add(first)
        #expect(references(of: strongTable).map(\.path) == ["[0]"])

        let strongToWeak = NSMapTable<AnyObject, AnyObject>.strongToWeakObjects()
        strongToWeak.setObject(first, forKey: key)
        #expect(references(of: strongToWeak).map(\.path) == ["keys[0]"])

        let weakToStrong = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()
        weakToStrong.setObject(first, forKey: key)
        #expect(references(of: weakToStrong).map(\.path) == [#"["a long enough key to not be a tagged poi"]"#])
    }
}

// MARK: - Associated objects

nonisolated(unsafe) var retainedKey: UInt8 = 0
nonisolated(unsafe) var assignedKey: UInt8 = 0
nonisolated(unsafe) var swiftKey: UInt8 = 0

@Suite("Associated objects", .serialized)
struct AssociatedObjectTests {
    init() {
        AssociatedObjects.install(includeImage: { $0.contains(".xctest/") })
    }

    @Test("Retained associations are references, named by their key; assigned ones and removed ones are not")
    func fromObjectiveC() {
        let owner = NSObject(), retained = NSObject(), assigned = NSObject()
        LHFAssociate(owner, &retainedKey, retained, true)
        LHFAssociate(owner, &assignedKey, assigned, false)
        let found = references(of: owner)
        #expect(found.map(\.path) == ["associated retainedKey"])
        #expect(found.first?.object === retained)

        LHFAssociate(owner, &retainedKey, nil, true)
        #expect(references(of: owner).isEmpty)
        withExtendedLifetime(assigned) {}
    }

    @Test("Calls from Swift are seen too, and a cycle through an association is certain")
    func fromSwift() throws {
        let screen = Screen(), helper = Screen()
        helper.delegate = screen
        objc_setAssociatedObject(screen, &swiftKey, helper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        defer { helper.delegate = nil }
        let found = try #require(cycle(through: screen))
        #expect(found.isCertain)
        #expect(found.description == "Screen.associated swiftKey → Screen.delegate → Screen")
    }
}

#endif
