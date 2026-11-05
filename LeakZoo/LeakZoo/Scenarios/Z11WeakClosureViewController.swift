//
//  Z11WeakClosureViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z11 — NO LEAK. Same as Z01 but captures [weak self].
final class Z11WeakClosureViewController: ZooViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { [weak self] in self?.refresh() }
    }

    private func refresh() {}
}
