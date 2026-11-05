//
//  Z06CombineSinkViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import Combine
import UIKit

/// Z06 — LEAK (cycle). self → cancellables → sink → closure → self
final class Z06CombineSinkViewController: ZooViewController {
    private let refresh = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh
            .sink { self.reload() }
            .store(in: &cancellables)
    }

    private func reload() {}
}
