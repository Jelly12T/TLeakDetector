//
//  TLeakDetector.swift
//  TLeakDetector
//
//  Created by thachlh on 5/11/26.
//

#if LEAK_DETECTOR_ENABLED && canImport(UIKit)
import UIKit
import LeakCore

/// Public entry point. Call once at launch, inside `#if DEBUG`:
///
///     #if DEBUG
///     TLeakDetector.install()
///     #endif
@MainActor
public enum TLeakDetector {
    public static func install() {
        guard LeakCore.markInstalled() else { return }
        // Later sprints: install UIViewController hooks here.
    }

    public static var isInstalled: Bool { LeakCore.isInstalled }
}

#endif
