//
//  Z22TaskOutlivesScreenViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

/// Z22 — LEAK (task). The screen dies ([weak self]), but its Task never ends: the stream never finishes
/// and nobody cancels it. ZooEventBus.shared → stream → suspended Task.
final class Z22TaskOutlivesScreenViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { [weak self] in
            for await event in ZooEventBus.shared.events() {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: Int) {}
}
