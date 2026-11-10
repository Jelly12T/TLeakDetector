//
//  ChildHostViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Container for add/remove-child scenarios. The child is the object under test.
/// The host keeps no reference to the child after removing it.
final class ChildHostViewController: ZooViewController, ZooStepping {
    private var pendingChild: UIViewController?
    /// `false` breaks the UIKit containment contract, like a hand-written container that forgets it.
    private let callsWillMove: Bool

    init(logTag: String, child: UIViewController, callsWillMove: Bool = true) {
        pendingChild = child
        self.callsWillMove = callsWillMove
        super.init(logTag: logTag)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("Remove child", id: "zoo.removeChild") { [weak self] in self?.performNextStep(animated: true) }

        guard let child = pendingChild else { return }
        pendingChild = nil
        addChild(child)
        stack.addArrangedSubview(child.view)
        child.view.heightAnchor.constraint(equalToConstant: 120).isActive = true
        child.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        child.didMove(toParent: self)
    }

    func performNextStep(animated: Bool) {
        guard let child = children.first else { return }
        if callsWillMove { child.willMove(toParent: nil) }
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}
