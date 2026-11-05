//
//  ScenarioRouter.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Opens a scenario the way its case enters (push, present, child), and in
/// headless mode also closes it the way it exits.
@MainActor
final class ScenarioRouter {
    private unowned let nav: UINavigationController

    init(navigationController: UINavigationController) {
        nav = navigationController
    }

    @discardableResult
    func open(_ spec: ScenarioSpec, animated: Bool) -> UIViewController {
        guard let screen = ScenarioFactory.maker(for: spec.id)?() else {
            fatalError("No screen for \(spec.id)")
        }
        screen.title = spec.name
        switch spec.navigation {
        case .pushPop, .popToRoot, .addRemoveChild:
            nav.pushViewController(screen, animated: animated)
        case .presentDismiss:
            (screen as? ZooViewController)?.showsCloseButton = true
            nav.present(screen, animated: animated)
        }
        return screen
    }

    /// Opens then closes the scenario without user input (autorun).
    /// Holds no strong reference to the screens, so it cannot delay their deinit.
    func runHeadless(_ spec: ScenarioSpec) async {
        open(spec, animated: false)
        await pause()

        switch spec.navigation {
        case .pushPop:
            nav.popViewController(animated: false)
            ZooLog.log("close \(spec.id)")
        case .presentDismiss:
            ZooLog.log("close \(spec.id)")
            await withCheckedContinuation { done in nav.dismiss(animated: false) { done.resume() } }
        case .popToRoot:
            // Each level pushes the next; the last one pops to root.
            for _ in 0..<10 where nav.viewControllers.count > 1 {
                (nav.topViewController as? ZooStepping)?.performNextStep(animated: false)
                if nav.viewControllers.count == 1 { ZooLog.log("close \(spec.id)") }
                await pause()
            }
        case .addRemoveChild:
            (nav.topViewController as? ZooStepping)?.performNextStep(animated: false)
            ZooLog.log("close \(spec.id)")
            await pause()
            nav.popViewController(animated: false)
        }
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
