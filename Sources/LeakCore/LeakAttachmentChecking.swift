//
//  LeakAttachmentChecking.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED

/// Answers "is this object back in the live hierarchy?". LeakCore knows nothing about UIKit,
/// so LeakUIKit provides the real implementation.
@MainActor
package protocol LeakAttachmentChecking {
    func isAttached(_ object: AnyObject) -> Bool
}

/// For objects with no notion of hierarchy.
package struct NeverAttached: LeakAttachmentChecking {
    package init() {}
    package func isAttached(_ object: AnyObject) -> Bool { false }
}

#endif
