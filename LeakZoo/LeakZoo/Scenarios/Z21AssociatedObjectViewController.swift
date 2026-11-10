//
//  Z21AssociatedObjectViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import ObjectiveC
import UIKit

final class Z21Helper {
    var owner: UIViewController?
}

private var helperKey: UInt8 = 0

/// Z21 — LEAK (cycle). self → associated object → Z21Helper.owner → self.
/// No stored property shows it: only the objc_setAssociatedObject hook does.
final class Z21AssociatedObjectViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let helper = Z21Helper()
        helper.owner = self
        objc_setAssociatedObject(self, &helperKey, helper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
