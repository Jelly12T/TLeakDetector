import UIKit
#if DEBUG
import LeakUIKit
#endif

final class L29FeedViewModel: LabObject {}

final class L29Hub {
    static let shared = L29Hub()
    private var listeners: [AnyObject] = []

    func register(_ listener: AnyObject) {
        listeners.append(listener)
    }
}

/// L29 — LEAK (outlived). self → viewModel; L29Hub.shared.listeners → viewModel. The screen itself dies.
final class L29FeedViewController: LabViewController {
    private let viewModel = L29FeedViewModel(logTag: "L29.viewModel")

    override func viewDidLoad() {
        super.viewDidLoad()
        L29Hub.shared.register(viewModel)
    }
}

/// L30 — LEAK (outlived). Swift self → ObjC session; ObjC singleton LL30SessionRegistry → session.
final class L30CheckoutViewController: LabViewController {
    private let session = LL30AnalyticsSession(logTag: "L30.session")

    override func viewDidLoad() {
        super.viewDidLoad()
        LL30SessionRegistry.sharedInstance.add(session)
    }
}

/// Owned by the ObjC LL31CartViewController.
@objc final class L31CartViewModel: LLTaggedObject {}

@objc final class L31CartStore: NSObject {
    @objc static let shared = L31CartStore()
    private var attached: [L31CartViewModel] = []

    @objc func attach(_ viewModel: L31CartViewModel) {
        attached.append(viewModel)
    }
}

final class L33Store: LabObject {
    var reducer: L33Reducer?
}

final class L33Reducer: LabObject {
    let store: L33Store   // should be `unowned` or `weak`

    init(store: L33Store) {
        self.store = store
        super.init(logTag: "L33.reducer")
    }
}

/// L33 — LEAK (outlived, cycle). self → store ⇄ reducer. The screen itself dies.
final class L33SearchViewController: LabViewController {
    private let store = L33Store(logTag: "L33.store")

    override func viewDidLoad() {
        super.viewDidLoad()
        store.reducer = L33Reducer(store: store)
    }
}

/// L34 — LEAK (outlived, cycle). Swift self → ObjC tree root ⇄ leaf (strong `parent`).
final class L34OutlineViewController: LabViewController {
    private let tree = LL34Node(logTag: "L34.root")

    override func viewDidLoad() {
        super.viewDidLoad()
        tree.addChild(LL34Node(logTag: "L34.leaf"))
    }
}

/// L36 — NO LEAK. Swift self → ObjC folder → file, file → folder is weak.
final class L36FolderViewController: LabViewController {
    private let folder = LL36Folder(logTag: "L36.folder")

    override func viewDidLoad() {
        super.viewDidLoad()
        folder.addFile(LL36File(logTag: "L36.file"))
    }
}

final class L37Thumbnail: LabObject {
    override init(logTag: String) {
        super.init(logTag: logTag)
        #if DEBUG
        TLeakDetector.track(self)
        #endif
    }
}

final class L37ThumbnailCache {
    static let shared = L37ThumbnailCache()
    private var thumbnails: [L37Thumbnail] = []

    func keep(_ thumbnail: L37Thumbnail) {
        thumbnails.append(thumbnail)
    }
}

/// L37 — LEAK (budget). Each open hands a new tracked thumbnail to a cache that never evicts.
final class L37GalleryViewController: LabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        L37ThumbnailCache.shared.keep(L37Thumbnail(logTag: "L37.thumbnail"))
    }
}

final class L39Preview: LabObject {
    override init(logTag: String) {
        super.init(logTag: logTag)
        #if DEBUG
        TLeakDetector.track(self)
        #endif
    }
}

/// L39 — NO LEAK. A tracked object with budget 1, owned by the screen and released with it.
final class L39PreviewViewController: LabViewController {
    private let preview = L39Preview(logTag: "L39.preview")
}
