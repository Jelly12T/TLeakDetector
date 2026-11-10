//
//  Z17CachedViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

enum Z17ScreenCache {
    static var screen: Z17CachedViewController?
}

/// Z17 — ALLOWED. Z17ScreenCache.screen → self, on purpose: reopening reuses it.
/// Listed in `allowedTypes` in AppDelegate.
final class Z17CachedViewController: ZooViewController {
    static func cached() -> Z17CachedViewController {
        if let screen = Z17ScreenCache.screen { return screen }
        let screen = Z17CachedViewController(logTag: "Z17")
        Z17ScreenCache.screen = screen
        return screen
    }
}
