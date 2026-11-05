//
//  Z04ChildClosureViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z04 — LEAK (cycle). Child VC is removed from its parent but keeps itself alive:
/// child → onUpdate → closure → child
final class Z04ChildClosureViewController: ZooViewController {
    private var onUpdate: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onUpdate = { self.update() }
    }

    private func update() {}
}
