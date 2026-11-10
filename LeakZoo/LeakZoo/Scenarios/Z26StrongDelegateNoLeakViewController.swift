//
//  Z26StrongDelegateNoLeakViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit

protocol Z26ParserDelegate: AnyObject {
    func parserDidFinish()
}

final class Z26Parser {
    /// Strong: a classic mistake. Here its delegate is not the screen, so nothing leaks yet.
    var delegate: Z26ParserDelegate?
}

final class Z26Logger: Z26ParserDelegate {
    func parserDidFinish() {}
}

/// Z26 — NO LEAK, but a warning. self → parser → delegate logger: no cycle today, a leak the day the
/// screen becomes the delegate.
final class Z26StrongDelegateNoLeakViewController: ZooViewController {
    private let parser = Z26Parser()

    override func viewDidLoad() {
        super.viewDidLoad()
        parser.delegate = Z26Logger()
    }
}
