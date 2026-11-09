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

/// The leave event behind a mark.
package struct LeakContext: Sendable {
    package let trigger: LeakTrigger
    /// The view controller whose closing caused the mark.
    package let rootTypeName: String

    package init(trigger: LeakTrigger, rootTypeName: String) {
        self.trigger = trigger
        self.rootTypeName = rootTypeName
    }
}

/// "This object must die soon." Holds the object weakly only.
@MainActor
package final class LeakExpectation {
    package weak var object: AnyObject?
    package let objectID: ObjectIdentifier
    /// Captured at mark time: once the object is gone its type can no longer be asked.
    package let typeName: String
    /// How the object was reached from the root, e.g. `ProfileVC.view.subviews[2]`.
    package let path: String
    let markID: UInt64

    init(object: AnyObject, path: String, markID: UInt64) {
        self.object = object
        self.objectID = ObjectIdentifier(object)
        self.typeName = String(describing: type(of: object))
        self.path = path
        self.markID = markID
    }
}

/// Everything one leave event expects to die. Checked and reported together.
@MainActor
final class LeakMark {
    enum Stage { case waitingT1, waitingT2 }

    let id: UInt64
    weak var root: AnyObject?
    let context: LeakContext
    let markedAt: TimeInterval
    var stage: Stage = .waitingT1
    var members: [LeakExpectation] = []

    init(id: UInt64, root: AnyObject, context: LeakContext, markedAt: TimeInterval) {
        self.id = id
        self.root = root
        self.context = context
        self.markedAt = markedAt
    }
}

#endif
