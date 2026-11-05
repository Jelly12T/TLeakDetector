//
//  SceneDelegate.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let scenarios = ScenarioSpec.loadAll()
        let list = ScenarioListViewController(scenarios: scenarios)
        let nav = UINavigationController(rootViewController: list)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window

        if ProcessInfo.processInfo.arguments.contains("--autorun") {
            Task { await ZooAutorun.run(scenarios: scenarios, router: list.router) }
        }
    }
}
