//
//  Z01ClosurePropertyViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z01 — LEAK (cycle). self → onRefresh → closure → self
final class Z01ClosurePropertyViewController: ZooViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { self.refresh() }
    }

    private func refresh() {}
}
