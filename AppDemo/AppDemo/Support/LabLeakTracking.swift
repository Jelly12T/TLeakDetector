import Foundation
#if DEBUG
import LeakUIKit
#endif

/// `TLeakDetector.track(_:)` for Objective-C, which cannot import the Swift package.
@objc final class LabLeakTracking: NSObject {
    @objc static func track(_ object: AnyObject) {
        #if DEBUG
        TLeakDetector.track(object)
        #endif
    }
}
