//
//  Z02StrongDelegateViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

protocol Z02WorkerDelegate: AnyObject {
    func workerDidFinish()
}

final class Z02Worker {
    var delegate: Z02WorkerDelegate?   // should be `weak`
}

/// Z02 — LEAK (cycle). self → worker → delegate → self
final class Z02StrongDelegateViewController: ZooViewController, Z02WorkerDelegate {
    private let worker = Z02Worker()

    override func viewDidLoad() {
        super.viewDidLoad()
        worker.delegate = self
    }

    func workerDidFinish() {}
}
