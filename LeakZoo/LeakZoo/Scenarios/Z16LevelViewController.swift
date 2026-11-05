//
//  Z16LevelViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z16 — NO LEAK. Three plain levels, then popToRoot. All three deinit.
final class Z16LevelViewController: ZooViewController, ZooStepping {
    private let level: Int

    init(level: Int) {
        self.level = level
        super.init(logTag: "Z16.\(level)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if level < 3 {
            addButton("Next", id: "zoo.next") { [weak self] in self?.performNextStep(animated: true) }
        } else {
            addButton("Pop to root", id: "zoo.popToRoot") { [weak self] in self?.performNextStep(animated: true) }
        }
    }

    func performNextStep(animated: Bool) {
        if level < 3 {
            let next = Z16LevelViewController(level: level + 1)
            next.title = "Level \(level + 1)"
            navigationController?.pushViewController(next, animated: animated)
        } else {
            navigationController?.popToRootViewController(animated: animated)
        }
    }
}
