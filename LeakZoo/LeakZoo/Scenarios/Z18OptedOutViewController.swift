//
//  Z18OptedOutViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit
#if DEBUG
import LeakUIKit
#endif

enum Z18Keeper {
    static var screens: [UIViewController] = []
}

/// Z18 — ALLOWED. Z18Keeper.screens → self, on purpose. The type opts out with LeakOptOut.
final class Z18OptedOutViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Z18Keeper.screens.append(self)
    }
}

#if DEBUG
extension Z18OptedOutViewController: LeakOptOut {}
#endif
