//  ManualSalesEntry

import UIKit

protocol ItemSelectionDelegate: AnyObject {
    func itemSelection(_ controller: ItemSelectionTableViewController, didSelectItem item: Item)
    func itemSelection(
        _ controller: ItemSelectionTableViewController,
        didEnterUnknownItemName name: String
    )
}
class ItemSelectionTableViewController: UITableViewController {
    var items: [Item] = []
    var filteredItems: [Item] = []
    
    weak var delegate: ItemSelectionDelegate?
    let searchBar = UISearchBar(frame: .zero)
    override func viewDidLoad() {
        items = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        filteredItems = items
        super.viewDidLoad()
        tableView.backgroundColor = .systemGray6
        searchBar.placeholder = "Search or type Item"
        searchBar.sizeToFit()
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = true
        searchBar.barTintColor = .clear
        searchBar.backgroundColor = .clear
        tableView.tableHeaderView = searchBar
        searchBar.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        items = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        filteredItems = items
        tableView.reloadData()
    }
    
    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {
        let text = searchBar.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
                navigationController?.popViewController(animated: true)
                return
        }
        if let existing = items.first(where: {
            $0.name.caseInsensitiveCompare(text) == .orderedSame
        }) {
            delegate?.itemSelection(self, didSelectItem: existing)
        } else {
            delegate?.itemSelection(self, didEnterUnknownItemName: text)
        }

        navigationController?.popViewController(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    var showsCreateNew: Bool {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty && filteredItems.isEmpty
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredItems.count + (showsCreateNew ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        cell.contentView.backgroundColor = .cell
        cell.textLabel?.textColor = .label
        
        if indexPath.row < filteredItems.count {
            let item = filteredItems[indexPath.row]
            cell.textLabel?.text = item.name
            cell.detailTextLabel?.text = "Remaining stock: \(item.currentStock.cleanString) \(item.unit)"
            cell.detailTextLabel?.textColor = .systemGray
        } else {
            cell.textLabel?.text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            cell.detailTextLabel?.text = "Not found in Inventory"
            cell.detailTextLabel?.textColor = .systemOrange
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == (tableView.numberOfRows(inSection: indexPath.section) - 1)
        cell.applyStandardCornerMask(isFirst: isFirst, isLast: isLast)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row < filteredItems.count {
            let selectedItem = filteredItems[indexPath.row]
            delegate?.itemSelection(self, didSelectItem: selectedItem)
        } else {
            let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            delegate?.itemSelection(self, didEnterUnknownItemName: text)
        }
        navigationController?.popViewController(animated: true)
    }
}

extension ItemSelectionTableViewController: UISearchBarDelegate {

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter {
                $0.name.localizedCaseInsensitiveContains(text)
            }
        }

        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

