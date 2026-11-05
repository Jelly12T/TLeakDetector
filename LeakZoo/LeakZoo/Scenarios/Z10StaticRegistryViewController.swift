//
//  Z10StaticRegistryViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

enum Z10ScreenRegistry {
    static var screens: [UIViewController] = []
}

/// Z10 — LEAK (rooted). static Z10ScreenRegistry.screens → self. Never removed.
final class Z10StaticRegistryViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Z10ScreenRegistry.screens.append(self)
    }
}
