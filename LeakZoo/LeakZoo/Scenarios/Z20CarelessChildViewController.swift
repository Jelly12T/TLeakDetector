//
//  Z20CarelessChildViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

/// Z20 — LEAK, only the instance budget sees it. Same cycle as Z04, but the host removes the
/// child without `willMove(toParent: nil)`, so no leave event is seen and nothing is marked.
/// Budget 1 in AppDelegate: reported when the second instance loads.
final class Z20CarelessChildViewController: ZooViewController {
    private var onUpdate: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onUpdate = { self.update() }
    }

    private func update() {}
}
