//
//  ModuleName.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation

/// What `prunedModules` matches: the Swift module for Swift classes (`MyApp`, `Swift`, `Foundation`),
/// the image for Objective-C ones (`UIKitCore`, `CoreFoundation`, `libobjc.A`).
package func moduleName(of cls: AnyClass) -> String? {
    // Objective-C classes reach Swift as ObjCClassWrapper metadata (kind 0x305): naming them through the
    // Swift runtime costs about half a millisecond the first time, the image name does not.
    if unsafeBitCast(cls, to: UnsafeRawPointer.self).load(as: UInt.self) > 0x7FF {
        let qualified = String(reflecting: cls)
        if let dot = qualified.firstIndex(of: "."), !qualified[..<dot].contains("<") {
            return String(qualified[..<dot])
        }
    }
    guard let path = class_getImageName(cls) else { return nil }
    var name = String(cString: path).split(separator: "/").last.map(String.init) ?? ""
    // Xcode builds app code into `App.debug.dylib` in Debug.
    for suffix in [".dylib", ".debug"] where name.hasSuffix(suffix) {
        name.removeLast(suffix.count)
    }
    return name
}

#endif
