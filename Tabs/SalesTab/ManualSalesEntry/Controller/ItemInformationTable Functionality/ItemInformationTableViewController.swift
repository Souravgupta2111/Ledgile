//
//  ItemInformationTableViewController.swift
//  ManualSalesEntry
//
//  Created by GEU  on 02/02/26.
//

import UIKit

protocol ItemInformationDelegate: AnyObject {
    func itemInformation(
        _ controller: ItemInformationTableViewController,
        item: Item,
        quantity: Int,
        sellingPrice: Double
    )
    func incompleteItemEntered(
        _ controller: ItemInformationTableViewController,
        item: IncompleteSaleItem
    )
}

class ItemInformationTableViewController: UITableViewController {
    enum ItemEntryMode {
        case existingItem
        case incompleteItem
    }

    private var entryMode: ItemEntryMode = .incompleteItem
    private var selectedUnit: String?
    private var typedItemName: String?

    private var selectedItem: Item?
    private var quantity: Int = 0
    private var sellingPrice: Double = 0
    
    private var total: Double { Double(quantity) * sellingPrice }
    weak var delegate: ItemInformationDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = UIColor.systemGray6
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "LabelTextFieldTableViewCell")
    }
    
    @objc private func quantityChanged(_ sender: UITextField) {
        if let text = sender.text, let value = Int(text.replacingOccurrences(of: ",", with: ".")) {
            quantity = value
        } else {
            quantity = 0
        }
    }
    
    @objc private func rateChanged(_ sender: UITextField) {
        if let text = sender.text, let value = Double(text.replacingOccurrences(of: ",", with: ".")) {
            sellingPrice = value
        } else {
            sellingPrice = 0
        }
    }
    
    func didEnterUnknownItem(name: String) {
        entryMode = .incompleteItem
        selectedItem = nil
        typedItemName = name
        selectedUnit = nil
        sellingPrice = 0

        tableView.reloadData()
    }
    
    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {

        if entryMode == .existingItem, let item = selectedItem {
            delegate?.itemInformation(
                self,
                item: item,
                quantity: quantity,
                sellingPrice: sellingPrice
            )
        }
        else {
                // Incomplete item path
            guard
                let name = typedItemName,
                let unit = selectedUnit
            else { return }

            let incomplete = IncompleteSaleItem(
                id: UUID(),
                transactionID: UUID(), // inject from parent ideally
                transactionItemID: UUID(),
                itemName: name,
                quantity: quantity,
                sellingPricePerUnit: sellingPrice,
                isCompleted: false,
                completedAt: nil,
                unit: unit,
                costPricePerUnit: nil,
                supplierName: nil,
                expiryDate: nil,
                createdAt: Date()
            )
                // You MUST add this delegate method
                delegate?.incompleteItemEntered(self, item: incomplete)
            }

            navigationController?.popViewController(animated: true)
    }
    
}

extension ItemInformationTableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 4
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        switch indexPath.row {
            case 0:
                let cell: UITableViewCell
                if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                    cell = dequeued
                } else {
                    cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                }
                cell.selectionStyle = .default
                cell.textLabel?.text = "Item"
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.detailTextLabel?.textColor = .systemGray2
                cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
                if entryMode == .existingItem {
                    cell.detailTextLabel?.text = selectedItem?.name ?? "-"
                } else {
                    cell.detailTextLabel?.text = typedItemName ?? "Tap to Select"
                }
                cell.backgroundColor = .cell
                cell.contentView.backgroundColor = .cell
                cell.accessoryType = .disclosureIndicator
                return cell
            case 1:
                let cell: UITableViewCell
                if let dequeued = tableView.dequeueReusableCell(withIdentifier: "rightDetail") {
                    cell = dequeued
                } else {
                    cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
                }
                cell.selectionStyle = .default
                cell.textLabel?.text = "Unit"
                cell.textLabel?.font = .preferredFont(forTextStyle: .body)
                cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
                cell.detailTextLabel?.textColor = .systemGray2
                cell.contentView.backgroundColor = .cell
                cell.backgroundColor = .cell

                if entryMode == .existingItem {
                    cell.detailTextLabel?.text = selectedItem?.unit ?? "-"
                    
                } else {
                    cell.detailTextLabel?.text = selectedUnit ?? "Tap to Select"
                }
                cell.accessoryType = .disclosureIndicator
                return cell

            case 2:
                let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                cell.titleLabel.text = "Quantity"
                cell.titleLabel.textColor = .systemRed
                cell.textField.placeholder = "0"

                cell.textField.text = quantity > 0 ? String(quantity) : nil
                cell.textField.addTarget(self, action: #selector(quantityChanged(_:)), for: .editingChanged)
                cell.textField.keyboardType = .numberPad

                return cell
            case 3:
                let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
                cell.titleLabel.text = "Rate"
                cell.textField.placeholder = "Rs 0"
                cell.textField.text = sellingPrice > 0 ? String(sellingPrice) : nil
                cell.textField.addTarget(self, action: #selector(rateChanged(_:)), for: .editingChanged)
                cell.textField.keyboardType = .decimalPad
                return cell
            default:
                break
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            performSegue(withIdentifier: "item_selection", sender: nil)
        }
        else if indexPath.row == 1 && entryMode == .incompleteItem {
            performSegue(withIdentifier: "unit_selection", sender: nil)
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_selection" {
            if let dest = segue.destination as? ItemSelectionTableViewController {
                dest.delegate = self
            }
        }
        else if segue.identifier == "unit_selection" {
            if let dest = segue.destination as? UnitSelectionTableViewController {
                dest.unitDelegate = self
            }
        }
    }
}

extension ItemInformationTableViewController: ItemSelectionDelegate {
    func itemSelection(_ controller: ItemSelectionTableViewController, didSelectItem item: Item) {
        entryMode = .existingItem
        selectedItem = item
        typedItemName = nil
        selectedUnit = nil
        sellingPrice = item.defaultSellingPrice
        
        // Reload affected rows
        let indexPathItem = IndexPath(row: 0, section: 0)
        let indexPathUnit = IndexPath(row: 1, section: 0)
        let indexPathRate = IndexPath(row: 3, section: 0)

        if let visible = tableView.indexPathsForVisibleRows {
            var toReload: [IndexPath] = []

            if visible.contains(indexPathItem) { toReload.append(indexPathItem) }
            if visible.contains(indexPathUnit) { toReload.append(indexPathUnit) }
            if visible.contains(indexPathRate) { toReload.append(indexPathRate) }

            tableView.reloadRows(at: toReload, with: .automatic)
        } else {
            tableView.reloadData()
        }
    }
    func itemSelection(_ controller: ItemSelectionTableViewController, didEnterUnknownItemName name: String) {
        entryMode = .incompleteItem
        typedItemName = name
        let indexPathItem = IndexPath(row: 0, section: 0)
        if tableView.indexPathsForVisibleRows?.contains(indexPathItem) == true {
            tableView.reloadRows(at: [indexPathItem], with: .automatic)
        } else {
            tableView.reloadData()
        }
    }
}
extension ItemInformationTableViewController: UnitSelectionDelegate {
    func unitSelection(_ controller: UnitSelectionTableViewController, unit: String) {
        guard entryMode == .incompleteItem else { return }
        selectedUnit = unit
        let indexPathUnit = IndexPath(row: 1, section: 0)
        tableView.reloadRows(at: [indexPathUnit], with: .automatic)
    }
}

