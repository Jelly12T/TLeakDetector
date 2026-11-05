//
//  Z08NotificationObserverViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z08 — LEAK (rooted). NotificationCenter → observer → block → self. Never removed.
final class Z08NotificationObserverViewController: ZooViewController {
    private var observer: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            self.reload()
        }
    }

    private func reload() {}
}
