//
//  Z07TimerViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z07 — LEAK (rooted). RunLoop → Timer → closure → self. Never invalidated.
final class Z07TimerViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.tick() }
    }

    private func tick() {}
}
