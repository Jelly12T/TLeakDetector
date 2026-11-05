//
//  Z14AsyncAfterViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Z14 — NO LEAK, delayed release. The block holds self for 1 s after the
/// screen closes, then deinit runs. A detector must not report this as a leak.
final class Z14AsyncAfterViewController: ZooViewController {
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.flush() }
    }

    private func flush() {}
}
