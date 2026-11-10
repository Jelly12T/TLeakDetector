import UIKit

/// Opens a scenario the way it enters (push, present), and in headless mode runs its step
/// and closes it the way it exits.
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
        if screen.title == nil { screen.title = spec.name }
        if spec.navigation.presents {
            (screen as? LLScreen)?.showsCloseButton = true
            nav.present(screen, animated: animated)
        } else {
            nav.pushViewController(screen, animated: animated)
        }
        return screen
    }

    /// Opens, steps and closes the scenario without user input (autorun).
    /// Holds no strong reference to the screens, so it cannot delay their deinit.
    func runHeadless(_ spec: ScenarioSpec) async {
        open(spec, animated: false)
        await pause()
        if spec.navigation.hasStep {
            let screen = spec.navigation.presents ? nav.presentedViewController : nav.topViewController
            (screen as? LLStepping)?.performNextStep(animated: false)
            await pause()
        }
        LabLog.log("close \(spec.id)")
        if spec.navigation.presents {
            await withCheckedContinuation { done in nav.dismiss(animated: false) { done.resume() } }
        } else {
            nav.popViewController(animated: false)
        }
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
