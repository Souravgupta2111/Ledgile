import UIKit

class RevenueViewController: UIViewController {

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
    
    @IBOutlet var tableView: UITableView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGray6
        tableView.sectionHeaderTopPadding = 8
        tableView.separatorStyle = .none
        tableView.tableFooterView = UIView(frame: .zero)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let all = AppDataModel.shared.dataModel.getRecentTransactions(limit: 100)
        // Only include sale transactions
        transactions = all.filter { entry in
            entry.transaction.type == .sale
        }
        tableView.reloadData()
    }
}
