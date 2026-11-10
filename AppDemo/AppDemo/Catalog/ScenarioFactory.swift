import UIKit

/// Maps a scenario id to the first screen it opens. Returns a maker, so the id
/// can be checked at launch without creating (and deinit-logging) a screen.
enum ScenarioFactory {
    static func maker(for id: String) -> (() -> UIViewController)? {
        switch id {
        // Objective-C screens
        case "L01": return { LL01BlockPropertyViewController(logTag: "L01") }
        case "L02": return { LL02StrongDelegateViewController(logTag: "L02") }
        case "L03": return { LL03WeakDelegateViewController(logTag: "L03") }
        case "L04": return { LL04TimerTargetViewController(logTag: "L04") }
        case "L05": return { LL05WeakProxyTimerViewController(logTag: "L05") }
        case "L06": return { LL06ObserverBlockViewController(logTag: "L06") }
        case "L07": return { LL07ObserverRemovedViewController(logTag: "L07") }
        case "L08": return { LL08ObserverNotRemovedViewController(logTag: "L08") }
        case "L09": return { LL09KVONotRemovedViewController(logTag: "L09") }
        case "L10": return { LL10DispatchAfterViewController(logTag: "L10") }
        case "L11": return { LL11LongDispatchAfterViewController(logTag: "L11") }
        case "L12": return { LL12WeakStrongDanceViewController(logTag: "L12") }
        case "L13": return { LL13SuppressedLegacyViewController(logTag: "L13") }
        // Cross-language cycles
        case "L14": return { LL14ProfileViewController(logTag: "L14") }
        case "L15": return { L15DownloadViewController(logTag: "L15") }
        case "L16": return { L16UploadViewController(logTag: "L16") }
        case "L17": return { LL17SyncViewController(logTag: "L17") }
        case "L18": return { L18ThumbnailViewController(logTag: "L18") }
        case "L19": return { LL19SettingsViewController(logTag: "L19") }
        // Swift screens
        case "L20": return { L20KVOObservationViewController(logTag: "L20") }
        case "L21": return { L21LazyClosureViewController(logTag: "L21") }
        case "L22": return { L22NestedWeakViewController(logTag: "L22") }
        case "L23": return { L23MethodReferenceViewController(logTag: "L23") }
        case "L24": return { L24ParentViewController(logTag: "L24") }
        case "L25": return { L25CombineAssignViewController(logTag: "L25") }
        case "L26": return { L26DetachedPollingViewController(logTag: "L26") }
        case "L27": return { L27UnownedClosureViewController(logTag: "L27") }
        case "L28": return { L28AlertActionViewController(logTag: "L28") }
        // Objects owned by a screen
        case "L29": return { L29FeedViewController(logTag: "L29") }
        case "L30": return { L30CheckoutViewController(logTag: "L30") }
        case "L31": return { LL31CartViewController(logTag: "L31") }
        case "L32": return { LL32ComposeViewController(logTag: "L32") }
        case "L33": return { L33SearchViewController(logTag: "L33") }
        case "L34": return { L34OutlineViewController(logTag: "L34") }
        case "L35": return { LL35EditorViewController(logTag: "L35") }
        case "L36": return { L36FolderViewController(logTag: "L36") }
        case "L37": return { L37GalleryViewController(logTag: "L37") }
        case "L38": return { LL38LoginViewController(logTag: "L38") }
        case "L39": return { L39PreviewViewController(logTag: "L39") }
        case "L40": return { ChildHostViewController(logTag: "L40.host",
                                                   child: LL40CarelessChildViewController(logTag: "L40"),
                                                   callsWillMove: false) }
        // Statics
        case "L41": return { L41RouteCachedViewController(logTag: "L41") }
        case "L42": return { L42DeferredActionViewController(logTag: "L42") }
        case "L43": return { LL43HistoryViewController(logTag: "L43") }
        case "L44": return { L44ReceiptViewController(logTag: "L44") }
        case "L45": return { LL45CheckoutViewController(logTag: "L45") }
        case "L46": return { L46WeakStaticViewController(logTag: "L46") }
        // Singletons
        case "L47": return { LL47DashboardViewController(logTag: "L47") }
        case "L48": return { L48OrdersViewController(logTag: "L48") }
        case "L49": return { L49OrderHistoryViewController(logTag: "L49") }
        case "L50": return { LL50AvatarViewController(logTag: "L50") }
        case "L51": return { L51NotificationsViewController(logTag: "L51") }
        case "L52": return { LL52InboxViewController(logTag: "L52") }
        case "L53": return { LL53WeakInboxViewController(logTag: "L53") }
        case "L54": return { L54WeakNotificationsViewController(logTag: "L54") }
        case "L55": return { LL55CachedGalleryViewController.cachedGallery() }
        case "L56": return { LL56RetainedPlayerViewController(logTag: "L56") }
        case "L57": return { L57ArticleViewController(logTag: "L57") }
        case "L58": return { L58SettingsViewController(logTag: "L58") }
        case "L59": return { L59PhotoViewController(logTag: "L59") }
        // Realistic
        case "L60": return { L60CheckoutCoordinator.startFlow() }
        case "L61": return { L61ProfileCoordinator.start() }
        case "L62": return { L62ProfileCoordinator.start() }
        case "L63": return { L63BindingViewController(logTag: "L63") }
        case "L64": return { L64WeakBindingViewController(logTag: "L64") }
        case "L65": return { L65FeedViewController(logTag: "L65") }
        case "L66": return { LL66FeedViewController(logTag: "L66") }
        case "L67": return { L67WeakFeedViewController(logTag: "L67") }
        case "L68": return { L68WindowHostViewController(logTag: "L68.host") }
        case "L69": return { L69NavHostController() }
        case "L70": return { L70TabHostController() }
        case "L71": return { L71TabHostController() }
        case "L72": return { LL72LiveScoreViewController(logTag: "L72") }
        default: return nil
        }
    }
}
