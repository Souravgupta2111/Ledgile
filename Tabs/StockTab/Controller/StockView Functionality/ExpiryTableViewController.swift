import UIKit

class ExpiryTableViewController: UITableViewController {

    var alerts: [ExpiryAlert] = []
    let sections: [ExpiryAlert.ExpirySeverity] = [
        .expired,
        .critical,
        .warning,
        .notice
    ]
    var visibleSections: [ExpiryAlert.ExpirySeverity] {
        sections.filter { (groupedAlerts[$0]?.isEmpty == false) }
    }
    
    var groupedAlerts: [ExpiryAlert.ExpirySeverity: [ExpiryAlert]] {
        Dictionary(grouping: alerts, by: { $0.severity })
            .mapValues { $0.sorted { $0.daysUntilExpiry < $1.daysUntilExpiry } }
    }
    
   override func viewDidLoad() {
       super.viewDidLoad()
       tableView.backgroundColor = .systemGray6
       tableView.sectionHeaderTopPadding = 12
   }

   override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)
       alerts = (try? AppDataModel.shared.dataModel.getExpiryAlerts()) ?? []
       tableView.reloadData()
   }
    override func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let severity = visibleSections[section]
        return groupedAlerts[severity]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        let severity = visibleSections[indexPath.section]
        let items = groupedAlerts[severity] ?? []
        let alert = items[indexPath.row]

        var content = UIListContentConfiguration.subtitleCell()

        content.text = alert.itemName
        content.textProperties.font = .systemFont(ofSize: 17, weight: .medium)

        switch alert.severity {
        case .expired:
            content.textProperties.color = .systemRed
        case .critical:
            content.textProperties.color = .systemOrange
        case .warning:
            content.textProperties.color = .systemYellow
        case .notice:
            content.textProperties.color = .systemBlue
        }

        content.secondaryText = "Qty: \(alert.quantityRemaining) • \(alert.daysUntilExpiry) days left"
        content.secondaryTextProperties.font = .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        return cell
    }

   override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
       cell.backgroundColor = .systemBackground
   }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .blackWhite

        switch visibleSections[section] {
        case .expired: label.text = "Expired"
        case .critical: label.text = "Critical"
        case .warning: label.text = "Warning"
        case .notice: label.text = "Notice"
        }

        let container = UIView()
        container.backgroundColor = .systemGray6

        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        return container
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 32
    }
}
