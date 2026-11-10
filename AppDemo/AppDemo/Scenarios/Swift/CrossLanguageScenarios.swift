import UIKit

/// Owned by the ObjC LL14ProfileViewController, which sets `onChange` to a block capturing itself.
@objc final class L14ProfileViewModel: LLTaggedObject {
    @objc var onChange: (() -> Void)?
}

/// L15 — LEAK (cycle). Swift self → ObjC downloader → completion (Swift closure as block) → self.
final class L15DownloadViewController: LabViewController {
    private let downloader = LL15Downloader(logTag: "L15.downloader")

    override func viewDidLoad() {
        super.viewDidLoad()
        downloader.completion = { data in self.show(data) }
    }

    private func show(_ data: Data?) {}
}

/// L16 — LEAK (cycle). Swift self → ObjC uploader → delegate (strong ObjC property) → self.
final class L16UploadViewController: LabViewController, LL16UploaderDelegate {
    private let uploader = LL16Uploader(logTag: "L16.uploader")

    override func viewDidLoad() {
        super.viewDidLoad()
        uploader.delegate = self
    }

    func uploaderDidFinish(_ uploader: LL16Uploader) {}
}

@objc protocol L17SyncerDelegate: AnyObject {
    func syncerDidFinish()
}

/// Owned by the ObjC LL17SyncViewController, which makes itself the delegate.
@objc final class L17Syncer: LLTaggedObject {
    @objc var delegate: L17SyncerDelegate?   // should be `weak`
}

/// L18 — NO LEAK. Like L15 with `[weak self]`.
final class L18ThumbnailViewController: LabViewController {
    private let fetcher = LL18ThumbnailFetcher(logTag: "L18.fetcher")

    override func viewDidLoad() {
        super.viewDidLoad()
        fetcher.onThumbnail = { [weak self] data in self?.show(data) }
    }

    private func show(_ data: Data?) {}
}

/// Owned by the ObjC LL19SettingsViewController, which sets `onChange` with weakSelf.
@objc final class L19SettingsViewModel: LLTaggedObject {
    @objc var onChange: (() -> Void)?
}
