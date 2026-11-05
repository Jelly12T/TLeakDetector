//
//  Z03ButtonActionViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z03 — LEAK (cycle). self → view → button → UIAction → closure → self
final class Z03ButtonActionViewController: ZooViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let button = UIButton(type: .system)
        button.setTitle("Tap", for: .normal)
        button.addAction(UIAction { _ in self.didTap() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private func didTap() {}
}
