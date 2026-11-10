import UIKit

final class L60AppCoordinators {
    static let shared = L60AppCoordinators()
    var children: [AnyObject] = []
}

/// Registered with the app for the whole flow, keeps every screen it pushes; nobody ends the flow.
final class L60CheckoutCoordinator: LabObject {
    private var screens: [UIViewController] = []

    static func startFlow() -> UIViewController {
        let coordinator = L60CheckoutCoordinator(logTag: "L60.coordinator")
        L60AppCoordinators.shared.children.append(coordinator)
        let screen = L60CheckoutViewController(logTag: "L60")
        coordinator.screens.append(screen)
        return screen
    }
}

/// L60 — LEAK (rooted). L60AppCoordinators.shared → coordinator → screens → self.
final class L60CheckoutViewController: LabViewController {}

final class L61ProfileCoordinator: LabObject {
    var screen: L61ProfileViewController?   // should be `weak`

    static func start() -> UIViewController {
        let coordinator = L61ProfileCoordinator(logTag: "L61.coordinator")
        let screen = L61ProfileViewController(logTag: "L61")
        screen.coordinator = coordinator
        coordinator.screen = screen
        return screen
    }
}

/// L61 — LEAK (cycle). self → coordinator → screen → self.
final class L61ProfileViewController: LabViewController {
    var coordinator: L61ProfileCoordinator?
}

final class L62ProfileCoordinator: LabObject {
    weak var screen: L62ProfileViewController?

    static func start() -> UIViewController {
        let coordinator = L62ProfileCoordinator(logTag: "L62.coordinator")
        let screen = L62ProfileViewController(logTag: "L62")
        screen.coordinator = coordinator
        coordinator.screen = screen
        return screen
    }
}

/// L62 — NO LEAK. Like L61 with a weak back reference.
final class L62ProfileViewController: LabViewController {
    var coordinator: L62ProfileCoordinator?
}

/// Minimal MVVM binding box, as found in many codebases.
final class LabObservable<Value> {
    private var observers: [(Value) -> Void] = []
    var value: Value {
        didSet { observers.forEach { $0(value) } }
    }

    init(_ value: Value) {
        self.value = value
    }

    func bind(_ observer: @escaping (Value) -> Void) {
        observers.append(observer)
        observer(value)
    }
}

final class L63ProfileViewModel: LabObject {
    let name = LabObservable("Ada")
}

/// L63 — LEAK (cycle). self → viewModel → name (generic box) → observers → closure → self.
final class L63BindingViewController: LabViewController {
    private let viewModel = L63ProfileViewModel(logTag: "L63.viewModel")
    private let nameLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(nameLabel)
        viewModel.name.bind { self.nameLabel.text = $0 }
    }
}

final class L64ProfileViewModel: LabObject {
    let name = LabObservable("Grace")
}

/// L64 — NO LEAK. Like L63 with `[weak self]`.
final class L64WeakBindingViewController: LabViewController {
    private let viewModel = L64ProfileViewModel(logTag: "L64.viewModel")
    private let nameLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(nameLabel)
        viewModel.name.bind { [weak self] in self?.nameLabel.text = $0 }
    }
}

final class L65FeedCell: UITableViewCell {
    var onLike: (() -> Void)?
}

/// L65 — LEAK (cycle). self → view → tableView → cell → onLike → self.
final class L65FeedViewController: LabViewController, UITableViewDataSource {
    private let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(L65FeedCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        stack.addArrangedSubview(tableView)
        tableView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        tableView.widthAnchor.constraint(equalToConstant: 320).isActive = true
        tableView.layoutIfNeeded()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! L65FeedCell
        cell.textLabel?.text = "Post \(indexPath.row)"
        cell.onLike = { self.like(indexPath.row) }
        return cell
    }

    private func like(_ row: Int) {}
}

final class L67FeedCell: UITableViewCell {
    var onLike: (() -> Void)?
}

/// L67 — NO LEAK. Like L65 with `[weak self]`.
final class L67WeakFeedViewController: LabViewController, UITableViewDataSource {
    private let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(L67FeedCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        stack.addArrangedSubview(tableView)
        tableView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        tableView.widthAnchor.constraint(equalToConstant: 320).isActive = true
        tableView.layoutIfNeeded()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! L67FeedCell
        cell.textLabel?.text = "Post \(indexPath.row)"
        cell.onLike = { [weak self] in self?.like(indexPath.row) }
        return cell
    }

    private func like(_ row: Int) {}
}

/// Hosts a second window whose root gets replaced (the step), then torn down when the host closes.
final class L68WindowHostViewController: LabViewController, LLStepping {
    private var window: UIWindow?

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("Replace window root", id: "lab.step") { [weak self] in self?.performNextStep(animated: true) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard window == nil, let scene = view.window?.windowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 20, y: 140, width: 220, height: 220)
        window.windowLevel = .normal + 1
        window.rootViewController = L68OldRootViewController(logTag: "L68.oldRoot")
        window.isHidden = false
        self.window = window
    }

    func performNextStep(animated: Bool) {
        window?.rootViewController = L68NewRootViewController(logTag: "L68.newRoot")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
    }
}

/// L68 — LEAK (cycle). Replaced window root: self → onRefresh → self.
final class L68OldRootViewController: LabViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { self.reload() }
    }

    private func reload() {}
}

final class L68NewRootViewController: LabViewController {}

/// Presented navigation stack whose root is replaced with setViewControllers (the step).
final class L69NavHostController: UINavigationController, LLStepping {
    init() {
        super.init(rootViewController: LL69LegacyRootViewController(logTag: "L69.legacyRoot"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        LabLog.log("deinit L69.host")
    }

    func performNextStep(animated: Bool) {
        setViewControllers([L69FreshRootViewController(logTag: "L69.freshRoot")], animated: animated)
    }
}

final class L69FreshRootViewController: LabViewController {}

/// L70 — NO LEAK. A tab bar presented then dismissed, nothing replaced: control for L71.
final class L70TabHostController: UITabBarController {
    init() {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [L70FirstTabViewController(logTag: "L70.first"), L70SecondTabViewController(logTag: "L70.second")]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        LabLog.log("deinit L70.host")
    }
}

final class L70FirstTabViewController: LabViewController {}
final class L70SecondTabViewController: LabViewController {}

/// Presented tab bar whose first tab is replaced with setViewControllers (the step).
final class L71TabHostController: UITabBarController, LLStepping {
    init() {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [L71OldTabViewController(logTag: "L71.oldTab"), L71HomeTabViewController(logTag: "L71.home")]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        LabLog.log("deinit L71.host")
    }

    func performNextStep(animated: Bool) {
        let kept = Array((viewControllers ?? []).dropFirst())
        setViewControllers([L71NewTabViewController(logTag: "L71.newTab")] + kept, animated: animated)
    }
}

/// L71 — LEAK (cycle). Tab removed by setViewControllers: self → onRefresh → self.
final class L71OldTabViewController: LabViewController {
    private var onRefresh: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        onRefresh = { self.reload() }
    }

    private func reload() {}
}

final class L71HomeTabViewController: LabViewController {}
final class L71NewTabViewController: LabViewController {}

@objc final class L72ScoreFeed: NSObject {
    @MainActor @objc(listenForScreen:)
    static func listen(for screen: LL72LiveScoreViewController) {
        Task { [weak screen] in
            for await score in LabEndlessFeed.shared.values() {
                screen?.showScore(score)
            }
        }
    }
}
