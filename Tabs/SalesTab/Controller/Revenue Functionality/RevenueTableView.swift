import UIKit
extension RevenueViewController: UITableViewDataSource, UITableViewDelegate {
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
        
        let itemsInSection = sections[indexPath.section].items
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == itemsInSection.count - 1
        cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
        
        let entry = itemsInSection[indexPath.row]
        let tx = entry.transaction
        
        if let name = tx.customerName, !name.isEmpty {
            cell.itemNameLabel.text = name
        } else {
            cell.itemNameLabel.text = "Cash Sale"
        }
        
        let details = tx.toBillingDetails()
        if let firstItem = details.items.first {
            var quantityLabelText = "\(firstItem.itemName) x \(firstItem.quantity)"
            let itemCount = details.items.count
            if itemCount > 1 {
                quantityLabelText += " + \(itemCount - 1) more"
            }
            cell.quantityLabel.text = quantityLabelText
        } else {
            cell.quantityLabel.text = "Unknown"
        }
        
        cell.priceLabel.textColor = UIColor(named: "Lime Moss")!
        cell.priceLabel.text = "₹\(tx.totalAmount)"
        cell.separatorView.backgroundColor = .separator
        return cell
        
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

