//
//  Z12CancelledTaskViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z12 — NO LEAK. Same as Z09 but the Task is cancelled when the screen disappears.
final class Z12CancelledTaskViewController: ZooViewController {
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        task = Task {
            for await event in ZooEventBus.shared.events() {
                self.handle(event)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        task?.cancel()
    }

    private func handle(_ event: Int) {}
}
