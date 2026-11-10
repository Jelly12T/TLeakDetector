import Foundation

/// One row of `expected.json`, the single source of truth for the app and `scripts/demo-autorun.sh`.
struct ScenarioSpec: Decodable {
    enum Expectation: String, Decodable {
        /// The listed objects stay alive through a strong reference cycle.
        case leakCycle = "leak_cycle"
        /// The listed objects stay alive because something outside the screen holds them.
        case leakRooted = "leak_rooted"
        case noLeak = "no_leak"
        /// Outlives its screen on purpose and is configured as such: must not be reported.
        case allowed = "allowed"
        /// A leak listed in LeakSuppressions.json: only logged.
        case leakSuppressed = "leak_suppressed"
        /// A leak no leave event reveals: reported by the instance budget once `opens` reaches it.
        case leakBudget = "leak_budget"
        /// The screen dies, a task it started keeps running.
        case leakTask = "leak_task"
        /// The screen dies, a subscription it made stays registered.
        case leakSubscription = "leak_subscription"

        var isLeak: Bool { ![.noLeak, .allowed].contains(self) }
    }

    enum Navigation: String, Decodable {
        case pushPop = "push_pop"
        case presentDismiss = "present_dismiss"
        case addRemoveChild = "add_remove_child"
        case setViewControllers = "set_view_controllers"
        case replaceTabs = "replace_tabs"
        case replaceWindowRoot = "replace_window_root"

        var presents: Bool { [.presentDismiss, .setViewControllers, .replaceTabs].contains(self) }
        var hasStep: Bool { ![.pushPop, .presentDismiss].contains(self) }
    }

    struct TrackedObject: Decodable {
        let log: String
        let className: String
        let leaks: Bool
        /// The report a correct detector gives for this object: `screen`, `outlived` or `budget`.
        /// Absent: no report of its own (it is reported through another object).
        let kind: String?
    }

    let id: String
    let name: String
    let family: String
    let language: String
    let expectation: Expectation
    let navigation: Navigation
    let pattern: String
    let retainPath: String?
    let deinitDelaySeconds: Double?
    let opens: Int?
    let warnings: [String]?
    let objects: [TrackedObject]

    static func loadAll() -> [ScenarioSpec] {
        guard let url = Bundle.main.url(forResource: "expected", withExtension: "json") else {
            fatalError("expected.json is missing from the app bundle")
        }
        do {
            struct File: Decodable { let scenarios: [ScenarioSpec] }
            let specs = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).scenarios
            for spec in specs where ScenarioFactory.maker(for: spec.id) == nil {
                fatalError("expected.json has \(spec.id) but ScenarioFactory does not")
            }
            return specs
        } catch {
            fatalError("Cannot decode expected.json: \(error)")
        }
    }
}
