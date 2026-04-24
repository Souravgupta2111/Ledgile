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
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }
}

