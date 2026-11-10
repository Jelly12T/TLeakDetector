//
//  Z24SessionDelegateViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

/// Z24 — LEAK (cycle). self → session → delegate self. A URLSession retains its delegate until invalidated.
final class Z24SessionDelegateViewController: ZooViewController, URLSessionDelegate {
    private var session: URLSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }
}
