//  Table Screens

import UIKit

class RecentTransactionViewController: UIViewController {
    let calendar = Calendar.current
    var transactions: [(transaction: Transaction, itemsSummary: String)] = []
    
    var sections: [(date: Date, items: [(transaction: Transaction, itemsSummary: String)])] {
        let grouped = Dictionary(grouping: transactions) { entry in
            calendar.startOfDay(for: entry.transaction.date)
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = grouped[key]?.sorted { $0.transaction.date > $1.transaction.date } ?? []
            return (date: key, items: items)
        }
    }
    var headerDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
    @IBOutlet weak var tableView: UITableView!
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGray6
        tableView.separatorStyle = .none
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        transactions = AppDataModel.shared.dataModel.getRecentTransactions(limit: 50)
        tableView.reloadData()
    }
}
