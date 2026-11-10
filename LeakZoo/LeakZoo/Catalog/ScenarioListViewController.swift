//
//  ScenarioListViewController.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

final class ScenarioListViewController: UITableViewController {
    private let scenarios: [ScenarioSpec]
    private(set) lazy var router = ScenarioRouter(navigationController: navigationController!)

    init(scenarios: [ScenarioSpec]) {
        self.scenarios = scenarios
        super.init(style: .insetGrouped)
        title = "Leak Zoo"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        scenarios.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let spec = scenarios[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.textLabel?.text = "\(spec.id)  \(spec.name)"
        cell.detailTextLabel?.text = "\(spec.expectation.rawValue) · \(spec.navigation.rawValue)"
        cell.detailTextLabel?.textColor = switch spec.expectation {
        case .noLeak, .allowed: .systemGreen
        case .leakSuppressed: .systemOrange
        case .leakCycle, .leakRooted, .leakBudget, .leakTask, .leakSubscription: .systemRed
        }
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "zoo.row.\(spec.id)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        router.open(scenarios[indexPath.row], animated: true)
    }
}
