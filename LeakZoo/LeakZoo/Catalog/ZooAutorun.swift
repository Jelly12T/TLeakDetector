//
//  ZooAutorun.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import Foundation

/// Launch with `--autorun` to open and close every scenario automatically.
/// `scripts/zoo-autorun.sh` reads the log and compares it with expected.json.
@MainActor
enum ZooAutorun {
    static func run(scenarios: [ScenarioSpec], router: ScenarioRouter) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        ZooLog.log("autorun start")
        for spec in scenarios {
            for _ in 0..<(spec.opens ?? 1) {
                ZooLog.log("open \(spec.id)")
                await router.runHeadless(spec)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        // Longer than the slowest delayed release (Z14, about 1 s).
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        ZooLog.log("autorun done")
    }
}
