import UIKit

protocol SupplierSelectionDelegate: AnyObject {
    func didSelectSupplier(name: String)
}

class SupplierSelectionViewController: UIViewController,
                                       UITableViewDelegate,
                                       UITableViewDataSource,
                                       UISearchBarDelegate {

    @IBOutlet weak var tableView: UITableView!
    let searchBar = UISearchBar(frame: .zero)

    weak var delegate: SupplierSelectionDelegate?

    var allSuppliers: [Supplier] = []
    var filteredSuppliers: [Supplier] = []


    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Supplier"

        tableView.delegate = self
        tableView.dataSource = self

        tableView.backgroundColor = .systemGray6
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag

        searchBar.placeholder = "Search or type supplier name"
        searchBar.sizeToFit()
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = false
        searchBar.barTintColor = .systemGray6
        searchBar.backgroundColor = .systemGray6
        
        searchBar.searchTextField.backgroundColor = .systemBackground

        tableView.tableHeaderView = searchBar
        searchBar.delegate = self

        tableView.register(
            UINib(nibName: "ItemTableViewCell", bundle: nil),
            forCellReuseIdentifier: "ItemTableViewCell"
        )

        loadSuppliers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSuppliers()
    }


    func loadSuppliers() {
        allSuppliers = CreditStore.shared.getAllSuppliers()
        filteredSuppliers = allSuppliers
        tableView.reloadData()
    }


    @IBAction func doneTapped(_ sender: UIBarButtonItem) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !text.isEmpty {
            delegate?.didSelectSupplier(name: text)
        }

        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }


    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {

        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            filteredSuppliers = allSuppliers
        } else {
            filteredSuppliers = allSuppliers.filter {
                $0.name.localizedCaseInsensitiveContains(text)
            }
        }

        UIView.performWithoutAnimation {
            tableView.reloadData()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {

        let text = searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            searchBar.resignFirstResponder()
            return
        }

        delegate?.didSelectSupplier(name: text)
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }


    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return filteredSuppliers.count
    }

    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {

        cell.backgroundColor = .systemBackground
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ItemTableViewCell",
            for: indexPath
        ) as! ItemTableViewCell

        let supplier = filteredSuppliers[indexPath.row]

        cell.itemNameLabel.text = supplier.name

        let balance = supplier.netBalance

        if balance > 0 {
            cell.quantityLabel.text = String(format: "₹%.0f payable", balance)
            cell.quantityLabel.textColor = .systemRed
        } else if balance < 0 {
            cell.quantityLabel.text = String(format: "₹%.0f receivable", -balance)
            cell.quantityLabel.textColor = .systemGreen
        } else {
            cell.quantityLabel.text = "₹0"
            cell.quantityLabel.textColor = .systemGray3
        }

        cell.priceLabel.isHidden = true
        cell.symbolView.isHidden = true
        
        cell.applySectionCornerMask(
            isFirst: indexPath.row == 0,
            isLast: indexPath.row == filteredSuppliers.count - 1
        )

        return cell
    }

    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {

        tableView.deselectRow(at: indexPath, animated: true)

        let supplier = filteredSuppliers[indexPath.row]

        delegate?.didSelectSupplier(name: supplier.name)
        navigationController?.popViewController(animated: true)
    }
}
