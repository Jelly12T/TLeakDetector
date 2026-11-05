//
//  Z13InvalidatedTimerViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z13 — NO LEAK. Same as Z07 but the timer is invalidated when the screen disappears.
final class Z13InvalidatedTimerViewController: ZooViewController {
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.tick() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func tick() {}
}
