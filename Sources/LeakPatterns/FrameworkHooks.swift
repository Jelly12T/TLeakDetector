//
//  FrameworkHooks.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import ObjectiveC

/// Replaces creating and removing methods with blocks that call the original, then record or forget the
/// hold. Classes are looked up by name: an app that does not link WebKit or QuartzCore has nothing to hook.
enum FrameworkHooks {
    static func install(into holds: FrameworkHolds) {
        timers(holds)
        displayLinks(holds)
        observers(holds)
        sessions(holds)
        scriptMessageHandlers(holds)
    }

    // MARK: - Timer

    private static func timers(_ holds: FrameworkHolds) {
        typealias TargetIMP = @convention(c) (AnyObject, Selector, Double, AnyObject, Selector, AnyObject?, Bool) -> Timer
        typealias TargetBlock = @convention(block) (AnyObject, Double, AnyObject, Selector, AnyObject?, Bool) -> Timer
        for name in ["scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:",
                     "timerWithTimeInterval:target:selector:userInfo:repeats:"] {
            let selector = NSSelectorFromString(name)
            replace(Timer.self, selector, classMethod: true) { imp in
                let original = unsafeBitCast(imp, to: TargetIMP.self)
                let block: TargetBlock = { cls, interval, target, action, info, repeats in
                    let timer = original(cls, selector, interval, target, action, info, repeats)
                    holds.record(.init(.timerTarget, holder: timer, referent: target))
                    return timer
                }
                return block
            }
        }

        typealias BlockIMP = @convention(c) (AnyObject, Selector, Double, Bool, AnyObject) -> Timer
        typealias BlockBlock = @convention(block) (AnyObject, Double, Bool, AnyObject) -> Timer
        for name in ["scheduledTimerWithTimeInterval:repeats:block:", "timerWithTimeInterval:repeats:block:"] {
            let selector = NSSelectorFromString(name)
            replace(Timer.self, selector, classMethod: true) { imp in
                let original = unsafeBitCast(imp, to: BlockIMP.self)
                let block: BlockBlock = { cls, interval, repeats, work in
                    // The copy the timer keeps: a block passed from Swift may still be on the stack.
                    let heapBlock = heapCopy(work)
                    let timer = original(cls, selector, interval, repeats, heapBlock)
                    holds.record(.init(.timerBlock, holder: timer, referent: heapBlock))
                    return timer
                }
                return block
            }
        }
    }

    // MARK: - CADisplayLink

    private static func displayLinks(_ holds: FrameworkHolds) {
        guard let cls = ObjCClasses.displayLink else { return }
        typealias CreateIMP = @convention(c) (AnyObject, Selector, AnyObject, Selector) -> AnyObject
        typealias CreateBlock = @convention(block) (AnyObject, AnyObject, Selector) -> AnyObject
        let create = NSSelectorFromString("displayLinkWithTarget:selector:")
        replace(cls, create, classMethod: true) { imp in
            let original = unsafeBitCast(imp, to: CreateIMP.self)
            let block: CreateBlock = { cls, target, action in
                let link = original(cls, create, target, action)
                holds.record(.init(.displayLink, holder: link, referent: target))
                return link
            }
            return block
        }
        typealias InvalidateIMP = @convention(c) (AnyObject, Selector) -> Void
        typealias InvalidateBlock = @convention(block) (AnyObject) -> Void
        let invalidate = NSSelectorFromString("invalidate")
        replace(cls, invalidate) { imp in
            let original = unsafeBitCast(imp, to: InvalidateIMP.self)
            let block: InvalidateBlock = { link in
                original(link, invalidate)
                holds.remove(holder: link) { _ in true }
            }
            return block
        }
    }

    // MARK: - NotificationCenter

    private static func observers(_ holds: FrameworkHolds) {
        typealias AddIMP = @convention(c) (AnyObject, Selector, NSString?, AnyObject?, AnyObject?, AnyObject) -> AnyObject
        typealias AddBlock = @convention(block) (AnyObject, NSString?, AnyObject?, AnyObject?, AnyObject) -> AnyObject
        let add = NSSelectorFromString("addObserverForName:object:queue:usingBlock:")
        replace(NotificationCenter.self, add) { imp in
            let original = unsafeBitCast(imp, to: AddIMP.self)
            let block: AddBlock = { center, name, object, queue, work in
                let heapBlock = heapCopy(work)
                let token = original(center, add, name, object, queue, heapBlock)
                holds.record(.init(.observer, holder: token, referent: heapBlock, name: name.map { $0 as String } ?? ""))
                return token
            }
            return block
        }

        typealias RemoveIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias RemoveBlock = @convention(block) (AnyObject, AnyObject) -> Void
        let remove = NSSelectorFromString("removeObserver:")
        replace(NotificationCenter.self, remove) { imp in
            let original = unsafeBitCast(imp, to: RemoveIMP.self)
            let block: RemoveBlock = { center, observer in
                original(center, remove, observer)
                holds.remove(holder: observer) { _ in true }
            }
            return block
        }

        typealias RemoveNamedIMP = @convention(c) (AnyObject, Selector, AnyObject, NSString?, AnyObject?) -> Void
        typealias RemoveNamedBlock = @convention(block) (AnyObject, AnyObject, NSString?, AnyObject?) -> Void
        let removeNamed = NSSelectorFromString("removeObserver:name:object:")
        replace(NotificationCenter.self, removeNamed) { imp in
            let original = unsafeBitCast(imp, to: RemoveNamedIMP.self)
            let block: RemoveNamedBlock = { center, observer, name, object in
                original(center, removeNamed, observer, name, object)
                holds.remove(holder: observer) { name == nil || $0.name == name.map { $0 as String } }
            }
            return block
        }
    }

    // MARK: - URLSession

    private static func sessions(_ holds: FrameworkHolds) {
        typealias CreateIMP = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?) -> AnyObject
        typealias CreateBlock = @convention(block) (AnyObject, AnyObject, AnyObject?, AnyObject?) -> AnyObject
        let create = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
        replace(URLSession.self, create, classMethod: true) { imp in
            let original = unsafeBitCast(imp, to: CreateIMP.self)
            let block: CreateBlock = { cls, configuration, delegate, queue in
                let session = original(cls, create, configuration, delegate, queue)
                if let delegate { holds.record(.init(.urlSession, holder: session, referent: delegate)) }
                return session
            }
            return block
        }
    }

    // MARK: - WKUserContentController

    private static func scriptMessageHandlers(_ holds: FrameworkHolds) {
        guard let cls = ObjCClasses.userContentController else { return }
        typealias AddIMP = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Void
        typealias AddBlock = @convention(block) (AnyObject, AnyObject, NSString) -> Void
        let add = NSSelectorFromString("addScriptMessageHandler:name:")
        replace(cls, add) { imp in
            let original = unsafeBitCast(imp, to: AddIMP.self)
            let block: AddBlock = { controller, handler, name in
                original(controller, add, handler, name)
                holds.record(.init(.scriptMessageHandler, holder: controller, referent: handler, name: name as String))
            }
            return block
        }
        typealias AddInWorldIMP = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, NSString) -> Void
        typealias AddInWorldBlock = @convention(block) (AnyObject, AnyObject, AnyObject, NSString) -> Void
        for name in ["addScriptMessageHandler:contentWorld:name:", "addScriptMessageHandlerWithReply:contentWorld:name:"] {
            let selector = NSSelectorFromString(name)
            replace(cls, selector) { imp in
                let original = unsafeBitCast(imp, to: AddInWorldIMP.self)
                let block: AddInWorldBlock = { controller, handler, world, name in
                    original(controller, selector, handler, world, name)
                    holds.record(.init(.scriptMessageHandler, holder: controller, referent: handler, name: name as String))
                }
                return block
            }
        }

        typealias RemoveIMP = @convention(c) (AnyObject, Selector, NSString) -> Void
        typealias RemoveBlock = @convention(block) (AnyObject, NSString) -> Void
        let remove = NSSelectorFromString("removeScriptMessageHandlerForName:")
        replace(cls, remove) { imp in
            let original = unsafeBitCast(imp, to: RemoveIMP.self)
            let block: RemoveBlock = { controller, name in
                original(controller, remove, name)
                holds.remove(holder: controller) { $0.name == name as String }
            }
            return block
        }
        typealias RemoveInWorldIMP = @convention(c) (AnyObject, Selector, NSString, AnyObject) -> Void
        typealias RemoveInWorldBlock = @convention(block) (AnyObject, NSString, AnyObject) -> Void
        let removeInWorld = NSSelectorFromString("removeScriptMessageHandlerForName:contentWorld:")
        replace(cls, removeInWorld) { imp in
            let original = unsafeBitCast(imp, to: RemoveInWorldIMP.self)
            let block: RemoveInWorldBlock = { controller, name, world in
                original(controller, removeInWorld, name, world)
                holds.remove(holder: controller) { $0.name == name as String }
            }
            return block
        }
        typealias RemoveAllIMP = @convention(c) (AnyObject, Selector) -> Void
        typealias RemoveAllBlock = @convention(block) (AnyObject) -> Void
        let removeAll = NSSelectorFromString("removeAllScriptMessageHandlers")
        replace(cls, removeAll) { imp in
            let original = unsafeBitCast(imp, to: RemoveAllIMP.self)
            let block: RemoveAllBlock = { controller in
                original(controller, removeAll)
                holds.remove(holder: controller) { _ in true }
            }
            return block
        }
        typealias RemoveAllInWorldIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias RemoveAllInWorldBlock = @convention(block) (AnyObject, AnyObject) -> Void
        let removeAllInWorld = NSSelectorFromString("removeAllScriptMessageHandlersFromContentWorld:")
        replace(cls, removeAllInWorld) { imp in
            let original = unsafeBitCast(imp, to: RemoveAllInWorldIMP.self)
            let block: RemoveAllInWorldBlock = { controller, world in
                original(controller, removeAllInWorld, world)
                holds.remove(holder: controller) { _ in true }
            }
            return block
        }
    }

    // MARK: - Helpers

    /// Replaces the method with a block built around its original implementation. A method inherited from a
    /// superclass is overridden in `cls` rather than replaced in the superclass.
    private static func replace(_ cls: AnyClass, _ selector: Selector, classMethod: Bool = false, _ make: (IMP) -> Any) {
        guard let target: AnyClass = classMethod ? object_getClass(cls) : cls,
              let method = class_getInstanceMethod(target, selector) else { return }
        let replacement = imp_implementationWithBlock(make(method_getImplementation(method)))
        if !class_addMethod(target, selector, replacement, method_getTypeEncoding(method)) {
            method_setImplementation(method, replacement)
        }
    }

    /// A heap block: copying one on the stack moves it, copying one on the heap retains it.
    private static func heapCopy(_ block: AnyObject) -> AnyObject {
        (block as? NSObject)?.copy() as AnyObject? ?? block
    }
}

#endif
