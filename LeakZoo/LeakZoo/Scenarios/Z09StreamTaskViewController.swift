//
//  Z09StreamTaskViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z09 — LEAK (rooted). ZooEventBus.shared → stream → suspended Task → self.
/// The stream never finishes and the Task is never cancelled.
final class Z09StreamTaskViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            for await event in ZooEventBus.shared.events() {
                self.handle(event)
            }
        }
    }

    private func handle(_ event: Int) {}
}
