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

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredItems.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.contentView.backgroundColor = .cell
        let item = filteredItems[indexPath.row]
        cell.textLabel?.text = item.name

        cell.textLabel?.textColor = .label
        return cell
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedItem = filteredItems[indexPath.row]
        delegate?.itemSelection(self, didSelectItem: selectedItem)
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

