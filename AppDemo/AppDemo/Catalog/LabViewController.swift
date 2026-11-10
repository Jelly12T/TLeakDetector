import UIKit

/// Base class of every Swift Lab screen: logs its deinit, shows a label and buttons.
/// It must not create or break any reference cycle itself.
class LabViewController: UIViewController, LLScreen {
    let logTag: String
    @objc var showsCloseButton = false
    let stack = UIStackView()

    init(logTag: String) {
        self.logTag = logTag
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        LabLog.log("deinit \(logTag)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "lab.screen.\(logTag)"

        let label = UILabel()
        label.text = [title, "\(logTag) (Swift)"].compactMap { $0 }.joined(separator: "\n")
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
            addButton("Close", id: "lab.close") { [weak self] in self?.dismiss(animated: true) }
        }
    }

    /// `handler` must not capture `self` strongly.
    func addButton(_ title: String, id: String, handler: @escaping () -> Void) {
        let button = UIButton(type: .system, primaryAction: UIAction(title: title) { _ in handler() })
        button.accessibilityIdentifier = id
        stack.addArrangedSubview(button)
    }
}
