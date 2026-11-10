//
//  Z23DisplayLinkViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import QuartzCore
import UIKit

/// Z23 — LEAK (rooted). RunLoop → CADisplayLink → target self. Never invalidated.
final class Z23DisplayLinkViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 1)
        link.add(to: .main, forMode: .common)
    }

    @objc private func step() {}
}
