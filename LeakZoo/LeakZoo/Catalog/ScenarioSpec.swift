//
//  ScenarioSpec.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import Foundation

/// One row of `expected.json`. That file is the single source of truth:
/// the app reads it, and the S8 UI tests read the same file.
struct ScenarioSpec: Decodable {
    enum Expectation: String, Decodable {
        case leakCycle = "leak_cycle"
        case leakRooted = "leak_rooted"
        case noLeak = "no_leak"
        /// Outlives its screen on purpose and is configured as such: must not be reported.
        case allowed = "allowed"
        /// A leak listed in LeakSuppressions.json: only logged.
        case leakSuppressed = "leak_suppressed"
        /// A leak no leave event reveals: reported by the instance budget once `opens` reaches it.
        case leakBudget = "leak_budget"
    }

    enum Navigation: String, Decodable {
        case pushPop = "push_pop"
        case presentDismiss = "present_dismiss"
        case popToRoot = "pop_to_root"
        case addRemoveChild = "add_remove_child"
    }

    /// A view controller the scenario creates, and whether it should outlive its screen.
    struct TrackedObject: Decodable {
        let log: String
        let className: String
        let leaks: Bool
    }

    let id: String
    let name: String
    let expectation: Expectation
    let navigation: Navigation
    let pattern: String
    let retainPath: String?
    let deinitDelaySeconds: Double?
    /// How many times the autorun opens and closes the scenario. Default 1.
    let opens: Int?
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
