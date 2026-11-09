//
//  LeakExpectation.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// What made us expect the object to die.
package enum LeakTrigger: String, Sendable {
    case pop
    case dismiss
    case removeFromParent
    case replaceRoot
    case manual
}

/// Where the object came from when it was marked.
package struct LeakContext: Sendable {
    package let trigger: LeakTrigger
    /// The view controller whose closing caused the mark.
    package let rootTypeName: String
    /// How the object was reached from the root, e.g. `ProfileVC.view.subviews[2]`.
    package let path: String

    package init(trigger: LeakTrigger, rootTypeName: String, path: String) {
        self.trigger = trigger
        self.rootTypeName = rootTypeName
        self.path = path
    }
}

/// "This object must die soon." Holds the object weakly only.
@MainActor
package final class LeakExpectation {
    package enum Stage { case waitingT1, waitingT2 }

    package weak var object: AnyObject?
    package let objectID: ObjectIdentifier
    /// Captured at mark time: once the object is gone its type can no longer be asked.
    package let typeName: String
    package private(set) var markedAt: TimeInterval
    package private(set) var context: LeakContext
    package private(set) var stage: Stage = .waitingT1
    /// Token of the only timer allowed to act on this expectation.
    package private(set) var token: UInt64

    init(object: AnyObject, context: LeakContext, markedAt: TimeInterval, token: UInt64) {
        self.object = object
        self.objectID = ObjectIdentifier(object)
        self.typeName = String(describing: type(of: object))
        self.markedAt = markedAt
        self.context = context
        self.token = token
    }

    func restart(context: LeakContext, markedAt: TimeInterval, token: UInt64) {
        self.context = context
        self.markedAt = markedAt
        self.stage = .waitingT1
        self.token = token
    }

    func advance(to stage: Stage, token: UInt64) {
        self.stage = stage
        self.token = token
    }
}

/// A confirmed suspicion: still alive and detached at T2.
package struct LeakReport: Sendable, CustomStringConvertible {
    package let typeName: String
    package let context: LeakContext
    package let markedAt: TimeInterval
    package let detectedAt: TimeInterval

    package var description: String {
        let age = String(format: "%.1f", detectedAt - markedAt)
        return "\(typeName) still alive \(age)s after \(context.trigger.rawValue) of \(context.rootTypeName) (path: \(context.path))"
    }
}

#endif
