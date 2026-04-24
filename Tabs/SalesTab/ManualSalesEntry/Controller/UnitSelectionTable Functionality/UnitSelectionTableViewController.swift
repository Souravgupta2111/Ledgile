//  ManualSalesEntry

import UIKit
protocol UnitSelectionDelegate: AnyObject {
    func unitSelection(_ controller: UnitSelectionTableViewController, unit: String)
}

class UnitSelectionTableViewController: UITableViewController {
    weak var unitDelegate: UnitSelectionDelegate?
    var units: [String] = [
        "Piece",
        "Dozen",
        "Gram",
        "Kilogram",
        "Milligram",
        "Pound",
        "Ounce",
        "Milliliter",
        "Liter",
        "Gallon",
        "Quart",
        "Pint",
        "Fluid Ounce",
        "Millimeter",
        "Centimeter",
        "Meter",
        "Inch",
        "Foot",
        "Yard",
        "Square Meter",
        "Square Foot",
        "Bottle",
        "Can",
        "Pair"
    ]

    let searchBar = UISearchBar(frame: .zero)
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGray6
        searchBar.placeholder = "Search or type Item"
        searchBar.sizeToFit()
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = true
        searchBar.barTintColor = .clear
        searchBar.backgroundColor = .clear
        tableView.tableHeaderView = searchBar
    }

}

extension UnitSelectionTableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return units.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = units[indexPath.row]
        cell.textLabel?.textColor = .label
        return cell
    }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedUnit = units[indexPath.row]
        unitDelegate?.unitSelection(self, unit: selectedUnit)
        navigationController?.popViewController(animated: true)
    }
}

extension UnitSelectionTableViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            searchBar.resignFirstResponder()
            return
        }
        if !units.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
            units.insert(text, at: 0)
            tableView.reloadData()
        }
        unitDelegate?.unitSelection(self, unit: text)
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Keep any needed state; currently no-op
    }
    
}
