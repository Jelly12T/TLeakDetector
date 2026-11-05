//
//  Z05PopToRootCycleViewControllers.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z05 — LEAK (cycle) on popToRoot. Level 1 is clean.
/// Level 2 → nextLevel → Level 3 → previousLevel → Level 2
final class Z05Level1ViewController: ZooViewController, ZooStepping {
    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("Next", id: "zoo.next") { [weak self] in self?.performNextStep(animated: true) }
    }

    func performNextStep(animated: Bool) {
        navigationController?.pushViewController(Z05Level2ViewController(logTag: "Z05.2"), animated: animated)
    }
}

final class Z05Level2ViewController: ZooViewController, ZooStepping {
    var nextLevel: Z05Level3ViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("Next", id: "zoo.next") { [weak self] in self?.performNextStep(animated: true) }
    }

    func performNextStep(animated: Bool) {
        let level3 = Z05Level3ViewController(logTag: "Z05.3")
        level3.previousLevel = self
        nextLevel = level3
        navigationController?.pushViewController(level3, animated: animated)
    }
}

final class Z05Level3ViewController: ZooViewController, ZooStepping {
    var previousLevel: Z05Level2ViewController?   // should be `weak`

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("Pop to root", id: "zoo.popToRoot") { [weak self] in self?.performNextStep(animated: true) }
    }

    func performNextStep(animated: Bool) {
        navigationController?.popToRootViewController(animated: animated)
    }
}
