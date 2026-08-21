import UIKit

class LowStockTableViewController: UITableViewController {
     var alerts: [LowStockAlert] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGray6
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        alerts = (try? AppDataModel.shared.dataModel.getLowStockAlerts()) ?? []
        tableView.reloadData()
        if alerts.isEmpty {
            tableView.setEmptyState(message: "No low stock alerts", icon: "checkmark.circle")
        } else {
            tableView.clearEmptyState()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return alerts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let alert = alerts[indexPath.row]
        
        var content = UIListContentConfiguration.subtitleCell()

        content.text = alert.itemName
        content.textProperties.font = .systemFont(ofSize: 17, weight: .regular)
        content.textProperties.color = .systemRed

        content.secondaryText = "Left: \(alert.currentStock) \(alert.unit) (Threshold: \(alert.threshold))"
        content.secondaryTextProperties.font = .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = alerts[indexPath.row]
        let profileVC: ItemProfileTableViewController
        if let storyboard,
           let vc = storyboard.instantiateViewController(withIdentifier: "ItemProfileTableViewController") as? ItemProfileTableViewController {
            profileVC = vc
        } else {
            profileVC = ItemProfileTableViewController(style: .insetGrouped)
        }
        profileVC.itemID = alert.itemID
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

