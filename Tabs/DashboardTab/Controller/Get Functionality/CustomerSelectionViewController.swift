import UIKit

protocol CustomerSelectionDelegate: AnyObject {
    func didSelectCustomer(name: String)
}

class CustomerSelectionViewController: UIViewController,
                                      UITableViewDelegate,
                                      UITableViewDataSource,
                                      UISearchBarDelegate {

    @IBOutlet weak var tableView: UITableView!
    let searchBar = UISearchBar(frame: .zero)
    weak var delegate: CustomerSelectionDelegate?

    private var allCustomers: [Customer] = []
    private var filteredCustomers: [Customer] = []

    @IBAction func doneTapped(_ sender: UIBarButtonItem) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !text.isEmpty {
            delegate?.didSelectCustomer(name: text)
        }

        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Customer"

        tableView.delegate = self
        tableView.dataSource = self

        tableView.backgroundColor = .systemGray6
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0

        searchBar.placeholder = "Search or type customer name"
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

        loadCustomers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCustomers()
    }

    func loadCustomers() {
        allCustomers = CreditStore.shared.getAllCustomers()
        filteredCustomers = allCustomers
        tableView.reloadData()
    }


    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {

        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            filteredCustomers = allCustomers
        } else {
            filteredCustomers = allCustomers.filter {
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

        delegate?.didSelectCustomer(name: text)
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }


    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return filteredCustomers.count
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .systemBackground
    }
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ItemTableViewCell",
            for: indexPath
        ) as! ItemTableViewCell

        let customer = filteredCustomers[indexPath.row]

        cell.itemNameLabel.text = customer.name

        let balance = customer.netBalance

        if balance > 0 {
            cell.quantityLabel.text = String(format: "₹%.0f pending", balance)
            cell.quantityLabel.textColor = .systemGreen
        } else if balance < 0 {
            cell.quantityLabel.text = String(format: "-₹%.0f", -balance)
            cell.quantityLabel.textColor = .systemRed
        } else {
            cell.quantityLabel.text = nil
        }

        cell.priceLabel.isHidden = true
        cell.symbolView.isHidden = true

        cell.applySectionCornerMask(
            isFirst: indexPath.row == 0,
            isLast: indexPath.row == filteredCustomers.count - 1
        )

        return cell
    }

    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {

        tableView.deselectRow(at: indexPath, animated: true)

        let customer = filteredCustomers[indexPath.row]

        delegate?.didSelectCustomer(name: customer.name)
        navigationController?.popViewController(animated: true)
    }
}
