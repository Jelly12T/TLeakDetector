import Foundation

/// Launch with `--autorun` to open and close every scenario automatically.
/// `scripts/demo-autorun.sh` reads the log and compares it with expected.json.
@MainActor
enum LabAutorun {
    static func run(scenarios: [ScenarioSpec], router: ScenarioRouter) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        LabLog.log("autorun start")
        for spec in scenarios {
            for _ in 0..<(spec.opens ?? 1) {
                LabLog.log("open \(spec.id)")
                await router.runHeadless(spec)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        let slowest = scenarios.compactMap(\.deinitDelaySeconds).max() ?? 0
        try? await Task.sleep(nanoseconds: UInt64((min(slowest, 5) + 2.5) * 1_000_000_000))
        LabLog.log("autorun done")
    }
}
