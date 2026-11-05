//
//  AppDelegate.swift
//  HostApp
//
//  Created by thachlh on 5/11/26.
//

import UIKit
#if DEBUG
import LeakUIKit
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        TLeakDetector.install()
        #endif

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
