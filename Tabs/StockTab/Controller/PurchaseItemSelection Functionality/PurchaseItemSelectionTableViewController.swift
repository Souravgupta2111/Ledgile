import UIKit

protocol PurchaseItemSelectionDelegate: AnyObject {
    func itemSelection(_ controller: PurchaseItemSelectionTableViewController, didSelectItem item: String)
}

class PurchaseItemSelectionTableViewController: UITableViewController {
    var items: [String] = []
    var filteredItems: [String] = []
    weak var delegate: PurchaseItemSelectionDelegate?
    let searchBar = UISearchBar(frame: .zero)
    override func viewDidLoad() {
        super.viewDidLoad()
        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        items = allItems.map { $0.name }
        filteredItems = items
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
        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        items = allItems.map { $0.name }
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
        delegate?.itemSelection(self, didSelectItem: text)
        navigationController?.popViewController(animated: true)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredItems.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = filteredItems[indexPath.row]
        cell.textLabel?.textColor = .label
        cell.contentView.backgroundColor = .cell
        return cell
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .white
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedItem = filteredItems[indexPath.row]
        delegate?.itemSelection(self, didSelectItem: selectedItem)
        navigationController?.popViewController(animated: true)
    }

    /*
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Pass the selected object to the new view controller.
    }
    */

}

extension PurchaseItemSelectionTableViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter {
                $0.localizedCaseInsensitiveContains(text)
            }
        }
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            searchBar.resignFirstResponder()
            return
        }
        if !items.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
            items.insert(text, at: 0)
            filteredItems = items
            tableView.reloadData()
        }
        delegate?.itemSelection(self, didSelectItem: text)
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }
}
