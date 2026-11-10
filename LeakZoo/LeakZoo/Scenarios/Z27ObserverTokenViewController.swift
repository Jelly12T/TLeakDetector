//
//  Z27ObserverTokenViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

/// Z27 — LEAK (subscription). The screen dies ([weak self]), its observer does not: never removed,
/// NotificationCenter → observer token → block stays registered forever.
final class Z27ObserverTokenViewController: ZooViewController {
    private var observer: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func reload() {}
}
