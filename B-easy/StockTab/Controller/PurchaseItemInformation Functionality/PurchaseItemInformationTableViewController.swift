//  Manual purchase entry item information.

import UIKit

protocol PurchaseItemInformationDelegate: AnyObject {
    func itemInformation(
        _ controller: PurchaseItemInformationTableViewController,
        entry: PurchaseEntry
    )
}

class PurchaseItemInformationTableViewController: UITableViewController {
    
    private var entry = PurchaseEntry()
    
    weak var delegate: PurchaseItemInformationDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = UIColor.systemGray6
        
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelTextFieldTableViewCell")
        tableView.register(UINib(nibName: "LabelDatePickerTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelDatePickerTableViewCell")
    }
    
    // MARK: - Done
    
    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {
        let itemName = (entry.selectedItemName ?? "").trimmingCharacters(in: .whitespaces)

        if itemName.isEmpty {
            showAlert(title: "Missing Item", message: "Please select an item.")
            return
        }

        if entry.quantity <= 0 {
            showAlert(title: "Invalid Quantity", message: "Enter quantity greater than 0.")
            return
        }

        if entry.costPrice <= 0 {
            showAlert(title: "Missing Cost Price", message: "Enter cost price.")
            return
        }

        delegate?.itemInformation(self, entry: entry)
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func closeButtonTapped(_ sender: UIBarButtonItem) {
        navigationController?.popViewController(animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - TableView

extension PurchaseItemInformationTableViewController {
    
    private enum Row {
        case item, unit, quantity, sellingPrice, costPrice, lowStock, expiry
    }

    private var visibleRows: [Row] {
        return [.item, .unit, .quantity, .sellingPrice, .costPrice, .lowStock, .expiry]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibleRows.count
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.01
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch visibleRows[indexPath.row] {

        case .item:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
            cell.textLabel?.text = "Item"
            cell.textLabel?.textColor = .systemRed
            
            if let name = entry.selectedItemName, !name.isEmpty {
                cell.detailTextLabel?.text = name
            } else {
                cell.detailTextLabel?.text = "Tap to Select"
                cell.detailTextLabel?.textColor = .systemGray2
            }
            
            cell.accessoryType = .disclosureIndicator
            return cell

        case .unit:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
            cell.textLabel?.text = "Unit"
            
            if let unit = entry.selectedUnitName, !unit.isEmpty {
                cell.detailTextLabel?.text = unit
            } else {
                cell.detailTextLabel?.text = "Tap to Select"
                cell.detailTextLabel?.textColor = .systemGray2
            }
            
            cell.accessoryType = .disclosureIndicator
            return cell

        case .quantity:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Quantity"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "0"
            cell.textField.text = entry.quantity > 0 ? String(entry.quantity) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.quantity = Double(text) ?? 0
            }
            return cell

        case .sellingPrice:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Selling Price"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.text = entry.sellingPrice > 0 ? String(entry.sellingPrice) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.sellingPrice = Double(text) ?? 0
            }
            return cell

        case .costPrice:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Cost Price"
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.text = entry.costPrice > 0 ? String(entry.costPrice) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.costPrice = Double(text) ?? 0
            }
            return cell

        case .lowStock:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Low Stock Alert"
            cell.textField.placeholder = "Enter count"
            cell.textField.text = entry.lowStockThreshold > 0 ? entry.lowStockThreshold.cleanString : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.lowStockThreshold = Double(text) ?? 0
            }
            return cell

        case .expiry:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelDatePickerTableViewCell", for: indexPath) as! LabelDatePickerTableViewCell
            cell.titleLabel.text = "Expiry Date"
            cell.datePicker.date = entry.expiryDate ?? Date()
            
            cell.onDateChanged = { [weak self] date in
                self?.entry.expiryDate = date
            }
            return cell
        }
    }
}


// MARK: - Selection

extension PurchaseItemInformationTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch visibleRows[indexPath.row] {
        case .item:
            performSegue(withIdentifier: "item_selection", sender: nil)
        case .unit:
            performSegue(withIdentifier: "unit_selection", sender: nil)
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_selection",
           let dest = segue.destination as? PurchaseItemSelectionTableViewController {
            dest.delegate = self
        }
        else if segue.identifier == "unit_selection",
                let dest = segue.destination as? PurchaseUnitSelectionTableViewController {
            dest.unitDelegate = self
        }
    }
}

// MARK: - Delegates

extension PurchaseItemInformationTableViewController: PurchaseItemSelectionDelegate {
    func itemSelection(_ controller: PurchaseItemSelectionTableViewController, didSelectItem item: String) {
        entry.selectedItemName = item
        tableView.reloadData()
    }
}

extension PurchaseItemInformationTableViewController: PurchaseUnitSelectionDelegate {
    func unitSelection(_ controller: PurchaseUnitSelectionTableViewController, unit: String) {
        entry.selectedUnitName = unit
        tableView.reloadData()
    }
}
