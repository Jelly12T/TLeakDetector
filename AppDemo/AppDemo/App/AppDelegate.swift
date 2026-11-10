import UIKit
#if DEBUG
import LeakUIKit
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        TLeakDetector.install(LeakConfiguration(
            allowedTypes: [LL55CachedGalleryViewController.self, L59SharedImageCache.self],
            instanceBudgets: [
                LeakInstanceBudget(L37Thumbnail.self, max: 1),
                LeakInstanceBudget(LL38SessionToken.self, max: 1),
                LeakInstanceBudget(L39Preview.self, max: 1),
                LeakInstanceBudget(LL40CarelessChildViewController.self, max: 1),
            ]))
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
