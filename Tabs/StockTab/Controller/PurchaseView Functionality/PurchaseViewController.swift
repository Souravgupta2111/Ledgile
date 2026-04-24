//  Table Screens

import UIKit

class PurchaseViewController: UIViewController {

    private let calendar = Calendar.current
    private var transactions: [(transaction: Transaction, itemsSummary: String)] = []
    
    private var sections: [(date: Date, items: [(transaction: Transaction, itemsSummary: String)])] {
        let grouped = Dictionary(grouping: transactions) { entry in
            calendar.startOfDay(for: entry.transaction.date)
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = grouped[key]?.sorted { $0.transaction.date > $1.transaction.date } ?? []
            return (date: key, items: items)
        }
    }

    private lazy var headerDateFormatter: DateFormatter = {
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
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemGray6
        tableView.sectionHeaderTopPadding = 8
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ItemTableViewCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let all = AppDataModel.shared.dataModel.getRecentTransactions(limit: 100)
        transactions = all.filter { $0.transaction.type == .purchase }
        tableView.reloadData()
    }
}

extension PurchaseViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let date = sections[section].date
        return headerDateFormatter.string(from: date)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemTableViewCell", for: indexPath) as! ItemTableViewCell
            
            let sectionItems = sections[indexPath.section].items
            let entry = sectionItems[indexPath.row]
            let tx = entry.transaction
            
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == sectionItems.count - 1
            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
            cell.itemNameLabel.text = tx.supplierName?.isEmpty == false ? tx.supplierName : "Purchase"
            
            let details = tx.toBillingDetails()
            if let firstItem = details.items.first {
                var text = "\(firstItem.itemName) x \(firstItem.quantity)"
                let itemCount = details.items.count
                
                if itemCount > 1 {
                    text += " + \(itemCount - 1) more"
                }
                cell.quantityLabel.text = text
            } else {
                cell.quantityLabel.text = "Unknown"
            }
            
            cell.priceLabel.textColor = .systemRed
            cell.priceLabel.text = "₹\(tx.totalAmount)"
            return cell
        }
        
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            cell.backgroundColor = .white
        }
        
        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            
            let entry = sections[indexPath.section].items[indexPath.row]
            let details = entry.transaction.toBillingDetails()
            
            let billVC = BillTableViewController(style: .plain)
            billVC.isReadOnly = true
            billVC.receiveBilling(details: details)
            
            let nav = UINavigationController(rootViewController: billVC)
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            present(nav, animated: true)
        }
}
