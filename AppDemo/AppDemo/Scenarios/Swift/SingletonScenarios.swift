import UIKit
#if DEBUG
import LeakUIKit
#endif

@objc final class L47Session: NSObject {
    @objc static let shared = L47Session()
    @objc var activeScreen: UIViewController?
}

/// L48 — LEAK (rooted). ObjC +sharedInstance (dispatch_once) → currentScreen → Swift self.
final class L48OrdersViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        LL48ScreenTracker.sharedInstance.currentScreen = self
    }
}

final class L49NetworkClient {
    static let shared = L49NetworkClient()
    private var pending: [UUID: (Result<Data, Error>) -> Void] = [:]

    /// The request never finishes, like one stuck behind a lost connection: the completion stays forever.
    func fetch(_ path: String, completion: @escaping (Result<Data, Error>) -> Void) {
        pending[UUID()] = completion
    }
}

/// L49 — LEAK (rooted). L49NetworkClient.shared.pending → completion → self.
final class L49OrderHistoryViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        L49NetworkClient.shared.fetch("/orders") { result in self.render(result) }
    }

    private func render(_ result: Result<Data, Error>) {}
}

protocol L51EventSubscriber: AnyObject {
    func handle(_ event: String)
}

final class L51EventBus {
    static let shared = L51EventBus()
    private var subscribers: [L51EventSubscriber] = []

    func subscribe(_ subscriber: L51EventSubscriber) {
        subscribers.append(subscriber)
    }
}

/// L51 — LEAK (rooted). L51EventBus.shared.subscribers → self, never unsubscribed.
final class L51NotificationsViewController: LabViewController, L51EventSubscriber {
    override func viewDidLoad() {
        super.viewDidLoad()
        L51EventBus.shared.subscribe(self)
    }

    func handle(_ event: String) {}
}

protocol L54EventSubscriber: AnyObject {
    func handle(_ event: String)
}

final class L54WeakEventBus {
    private struct Subscription {
        weak var subscriber: L54EventSubscriber?
    }

    static let shared = L54WeakEventBus()
    private var subscriptions: [Subscription] = []

    func subscribe(_ subscriber: L54EventSubscriber) {
        subscriptions.append(Subscription(subscriber: subscriber))
    }
}

/// L54 — NO LEAK. Like L51 with weak subscriptions.
final class L54WeakNotificationsViewController: LabViewController, L54EventSubscriber {
    override func viewDidLoad() {
        super.viewDidLoad()
        L54WeakEventBus.shared.subscribe(self)
    }

    func handle(_ event: String) {}
}

@objc final class L56MiniPlayerKeeper: NSObject {
    @objc static let shared = L56MiniPlayerKeeper()
    private var screens: [UIViewController] = []

    @objc func keep(_ screen: UIViewController) {
        screens.append(screen)
    }
}

#if DEBUG
extension LL56RetainedPlayerViewController: LeakOptOut {}
#endif

final class L57Analytics {
    static let shared = L57Analytics()
    func track(_ event: String) {}
}

/// L57 — NO LEAK. self → L57Analytics.shared: a singleton the screen uses, not one it owns.
final class L57ArticleViewController: LabViewController {
    private let analytics = L57Analytics.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        analytics.track("article.open")
    }
}

final class L58AppCoordinator {
    static let main = L58AppCoordinator()
}

/// L58 — NO LEAK. `weak var` to an app-lifetime coordinator.
final class L58SettingsViewController: LabViewController {
    weak var coordinator: L58AppCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        coordinator = L58AppCoordinator.main
    }
}

final class L59SharedImageCache {
    static let shared = L59SharedImageCache()
}

/// L59 — ALLOWED. Like L57, but the singleton's type is listed in `allowedTypes`.
final class L59PhotoViewController: LabViewController {
    private let cache = L59SharedImageCache.shared
}
