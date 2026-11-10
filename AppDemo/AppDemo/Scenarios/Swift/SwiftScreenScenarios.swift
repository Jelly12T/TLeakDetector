import Combine
import UIKit

final class L20Player: NSObject {
    @objc dynamic var volume: Double = 0
}

/// L20 — LEAK (cycle). self → observation (NSKeyValueObservation) → closure → self.
final class L20KVOObservationViewController: LabViewController {
    private let player = L20Player()
    private var observation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        observation = player.observe(\.volume) { _, _ in self.render() }
    }

    private func render() {}
}

/// L21 — LEAK (cycle). self → lazy closure storage → self.
final class L21LazyClosureViewController: LabViewController {
    private lazy var headline: () -> String = { self.logTag.uppercased() }

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = headline()
    }
}

/// L22 — LEAK (cycle). `[weak self]` only on the inner closure: the stored outer closure captures self strongly.
final class L22NestedWeakViewController: LabViewController {
    private var onTap: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onTap = {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    private func refresh() {}
}

final class L23ViewModel: LabObject {
    var onEvent: ((String) -> Void)?
}

/// L23 — LEAK (cycle). self → viewModel → onEvent (method reference `handle`, binds self) → self.
final class L23MethodReferenceViewController: LabViewController {
    private let viewModel = L23ViewModel(logTag: "L23.viewModel")

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.onEvent = handle
    }

    private func handle(_ event: String) {}
}

/// L24 — LEAK (cycle). parent → children[0] (UIKit) → child → parentScreen → parent.
final class L24ParentViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let child = L24ChildViewController(logTag: "L24.child")
        child.parentScreen = self
        addChild(child)
        stack.addArrangedSubview(child.view)
        child.view.heightAnchor.constraint(equalToConstant: 120).isActive = true
        child.didMove(toParent: self)
    }
}

final class L24ChildViewController: LabViewController {
    var parentScreen: L24ParentViewController?   // should be `weak`
}

/// L25 — LEAK (cycle). self → cancellables → Subscribers.Assign → self (`assign(to:on: self)`).
final class L25CombineAssignViewController: LabViewController {
    private let headlines = CurrentValueSubject<String, Never>("")
    private var cancellables: Set<AnyCancellable> = []
    var headline = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        headlines.assign(to: \.headline, on: self).store(in: &cancellables)
    }
}

/// L26 — LEAK (rooted). A detached Task polls forever and captures self strongly; nobody cancels it.
final class L26DetachedPollingViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.poll()
            }
        }
    }

    private func poll() {}
}

/// L27 — NO LEAK. Stored closure with `[unowned self]`.
final class L27UnownedClosureViewController: LabViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { [unowned self] in self.reload() }
    }

    private func reload() {}
}

/// L28 — LEAK (cycle). self → deleteAlert → UIAlertAction handler → self.
final class L28AlertActionViewController: LabViewController {
    private var deleteAlert: UIAlertController?

    override func viewDidLoad() {
        super.viewDidLoad()
        let alert = UIAlertController(title: "Delete draft?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in self.deleteDraft() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        deleteAlert = alert
    }

    private func deleteDraft() {}
}
