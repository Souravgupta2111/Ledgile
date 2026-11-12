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
    var filteredUnits: [String] = []

    let searchBar = UISearchBar(frame: .zero)
    override func viewDidLoad() {
        super.viewDidLoad()
        filteredUnits = units
        tableView.backgroundColor = .systemGray6
        searchBar.placeholder = "Search or type Unit"
        searchBar.sizeToFit()
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = true
        searchBar.barTintColor = .clear
        searchBar.backgroundColor = .clear
        searchBar.delegate = self
        tableView.tableHeaderView = searchBar
    }

}

extension UnitSelectionTableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    var showsCustomUnit: Bool {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty && !filteredUnits.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame })
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredUnits.count + (showsCustomUnit ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        if indexPath.row < filteredUnits.count {
            cell.textLabel?.text = filteredUnits[indexPath.row]
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = nil
        } else {
            let customText = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            cell.textLabel?.text = customText
            cell.textLabel?.textColor = .systemGreen
            cell.detailTextLabel?.text = "Custom Unit"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedUnit: String
        if indexPath.row < filteredUnits.count {
            selectedUnit = filteredUnits[indexPath.row]
        } else {
            selectedUnit = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        unitDelegate?.unitSelection(self, unit: selectedUnit)
        navigationController?.popViewController(animated: true)
    }
}

extension UnitSelectionTableViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            filteredUnits = units
        } else {
            filteredUnits = units.filter { $0.localizedCaseInsensitiveContains(text) }
        }
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            searchBar.resignFirstResponder()
            return
        }
        unitDelegate?.unitSelection(self, unit: text)
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Keep any needed state; currently no-op
    }
}
