//
//  Z19SuppressedLeakViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

/// Z19 — LEAK, SUPPRESSED. Same cycle as Z01: self → onRefresh → closure → self.
/// Listed in LeakSuppressions.json, so it is only logged until the entry expires.
final class Z19SuppressedLeakViewController: ZooViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { self.refresh() }
    }

    private func refresh() {}
}
