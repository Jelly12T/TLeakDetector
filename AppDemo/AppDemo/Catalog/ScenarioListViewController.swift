import UIKit

final class ScenarioListViewController: UITableViewController {
    private let sections: [(family: String, scenarios: [ScenarioSpec])]
    private(set) lazy var router = ScenarioRouter(navigationController: navigationController!)

    init(scenarios: [ScenarioSpec]) {
        var families: [String] = []
        var byFamily: [String: [ScenarioSpec]] = [:]
        for spec in scenarios {
            if byFamily[spec.family] == nil { families.append(spec.family) }
            byFamily[spec.family, default: []].append(spec)
        }
        sections = families.map { ($0, byFamily[$0]!) }
        super.init(style: .insetGrouped)
        title = "Leak Lab"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].family
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].scenarios.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let spec = sections[indexPath.section].scenarios[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.textLabel?.text = "\(spec.id)  \(spec.name)"
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = "\(spec.expectation.rawValue) · \(spec.navigation.rawValue) · \(spec.language)"
        cell.detailTextLabel?.textColor = switch spec.expectation {
        case .noLeak, .allowed: .systemGreen
        case .leakSuppressed: .systemOrange
        default: .systemRed
        }
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "lab.row.\(spec.id)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        router.open(sections[indexPath.section].scenarios[indexPath.row], animated: true)
    }
}
