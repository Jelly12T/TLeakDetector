import UIKit

enum L41ScreenCache {
    static var byRoute: [String: UIViewController] = [:]
}

/// L41 — LEAK (rooted). `static var` dictionary → self.
final class L41RouteCachedViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        L41ScreenCache.byRoute["/l41"] = self
    }
}

enum L42PendingActions {
    static var actions: [() -> Void] = []
}

/// L42 — LEAK (rooted). `static var` array of closures → closure → self.
final class L42DeferredActionViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        L42PendingActions.actions.append { self.refresh() }
    }

    private func refresh() {}
}

/// L44 — LEAK (rooted). ObjC function-local static dictionary → Swift self.
final class L44ReceiptViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        LL44RememberScreen(self)
    }
}

struct L46WeakBox {
    weak var screen: UIViewController?
}

enum L46RecentScreens {
    static var boxes: [L46WeakBox] = []
}

/// L46 — NO LEAK. `static var` array of weak boxes → self (weak).
final class L46WeakStaticViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        L46RecentScreens.boxes.append(L46WeakBox(screen: self))
    }
}
