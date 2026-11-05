//
//  ZooViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// A screen that takes more than one step to close (pop-to-root chains, child hosts).
/// Buttons call it, and so does the autorun.
@MainActor
protocol ZooStepping: AnyObject {
    func performNextStep(animated: Bool)
}

/// Base class of every Zoo screen: logs its deinit and shows a label and buttons.
/// It must not create or break any reference cycle itself.
class ZooViewController: UIViewController {
    let logTag: String
    /// Set by the router for presented screens.
    var showsCloseButton = false
    let stack = UIStackView()

    init(logTag: String) {
        self.logTag = logTag
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        ZooLog.log("deinit \(logTag)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "zoo.screen.\(logTag)"

        let label = UILabel()
        label.text = [title, logTag].compactMap { $0 }.joined(separator: "\n")
        label.numberOfLines = 0
        label.textAlignment = .center

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        if showsCloseButton {
            addButton("Close", id: "zoo.close") { [weak self] in self?.dismiss(animated: true) }
        }
    }

    /// `handler` must not capture `self` strongly.
    func addButton(_ title: String, id: String, handler: @escaping () -> Void) {
        let button = UIButton(type: .system, primaryAction: UIAction(title: title) { _ in handler() })
        button.accessibilityIdentifier = id
        stack.addArrangedSubview(button)
    }
}
