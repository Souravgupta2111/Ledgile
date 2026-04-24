import UIKit

final class GlobalSearchViewController: UITableViewController {
    private enum Section: CaseIterable {
        case customers
        case suppliers
        case items
        case transactions

        var title: String {
            switch self {
            case .customers: return "Customers"
            case .suppliers: return "Suppliers"
            case .items: return "Items"
            case .transactions: return "Transactions"
            }
        }
    }

    private enum Route: String {
        case bill = "bill_segue"
        case item = "item_segue"
        case customer = "customer_segue"
        case supplier = "supplier_segue"
    }
    
    private struct TransactionResult {
        let transaction: Transaction
        let billItemContext: String
    }

    private let dm = AppDataModel.shared.dataModel
    private let creditStore = CreditStore.shared

    private var allCustomers: [Customer] = []
    private var allSuppliers: [Supplier] = []
    private var allItems: [Item] = []
    private var allTransactions: [Transaction] = []
    private var transactionItemsByTransactionID: [UUID: [TransactionItem]] = [:]

    private var customerResults: [Customer] = []
    private var supplierResults: [Supplier] = []
    private var itemResults: [Item] = []
    private var transactionResults: [TransactionResult] = []

    private var currentQuery: String = ""
    private var isSearching: Bool { !currentQuery.isEmpty }

    private let afterSearchReuseID = "AfterSearchTableViewCell"

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.autocapitalizationType = .none
        controller.searchBar.searchBarStyle = .minimal
        controller.searchBar.placeholder = "Search"
        return controller
    }()

    private var visibleSections: [Section] {
        guard isSearching else { return [] }

        return Section.allCases.filter { section in
            switch section {
            case .customers: return !customerResults.isEmpty
            case .suppliers: return !supplierResults.isEmpty
            case .items: return !itemResults.isEmpty
            case .transactions: return !transactionResults.isEmpty
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        tableView.register(UINib(nibName: afterSearchReuseID, bundle: nil), forCellReuseIdentifier: afterSearchReuseID)
        tableView.keyboardDismissMode = .onDrag
        tableView.backgroundColor = .systemGroupedBackground
        tableView.sectionHeaderTopPadding = 8
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.contentInsetAdjustmentBehavior = .automatic
        definesPresentationContext = true

        loadData()
        updateBackgroundState()
    }

    private func loadData() {
        allCustomers = creditStore.getAllCustomers().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allSuppliers = creditStore.getAllSuppliers().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allItems = ((try? dm.db.getAllItems()) ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allTransactions = ((try? dm.db.getTransactions()) ?? []).sorted { $0.date > $1.date }

        transactionItemsByTransactionID = allTransactions.reduce(into: [:]) { partialResult, transaction in
            partialResult[transaction.id] = (try? dm.db.getTransactionItems(for: transaction.id)) ?? []
        }

        updateResults(for: "")
    }

    private func updateResults(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmedQuery

        guard !trimmedQuery.isEmpty else {
            customerResults = []
            supplierResults = []
            itemResults = []
            transactionResults = []
            tableView.reloadData()
            updateBackgroundState()
            return
        }

        customerResults = allCustomers.filter { customer in
            customer.name.localizedCaseInsensitiveContains(trimmedQuery)
            || (customer.phone?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }

        supplierResults = allSuppliers.filter { supplier in
            supplier.name.localizedCaseInsensitiveContains(trimmedQuery)
            || (supplier.phone?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }

        itemResults = allItems.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmedQuery)
            || item.unit.localizedCaseInsensitiveContains(trimmedQuery)
            || (item.barcode?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }

        transactionResults = allTransactions.compactMap { transaction in
            let customerName = transaction.customerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let supplierName = transaction.supplierName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let billItems = transactionItemsByTransactionID[transaction.id] ?? []

            let transactionText = [transaction.invoiceNumber, customerName ?? "", supplierName ?? ""].joined(separator: " ")

            let matchingBillItemNames = uniqueItemNames(
                billItems
                    .map(\.itemName)
                    .filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            )

            let transactionFieldMatched = transactionText.localizedCaseInsensitiveContains(trimmedQuery)
            guard transactionFieldMatched || !matchingBillItemNames.isEmpty else { return nil }

            let billItemContext: String
            if !matchingBillItemNames.isEmpty {
                billItemContext = "Matched item(s): \(matchingBillItemNames.joined(separator: ", "))"
            } else {
                let previewNames = uniqueItemNames(Array(billItems.map(\.itemName).prefix(3)))
                billItemContext = previewNames.isEmpty ? "No bill items" : "Bill item(s): \(previewNames.joined(separator: ", "))"
            }

            return TransactionResult(transaction: transaction, billItemContext: billItemContext)
        }

        tableView.reloadData()
        updateBackgroundState()
    }

    private func uniqueItemNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for name in names {
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            if seen.insert(key).inserted {
                result.append(cleaned)
            }
        }

        return result
    }

    private func updateBackgroundState() {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel

        if !isSearching {
            label.text = "Search for customer,item or sales"
            tableView.backgroundView = label
            return
        }

        if visibleSections.isEmpty {
            label.text = "No results found"
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let category = visibleSections[section]
        switch category {
        case .customers: return customerResults.count
        case .suppliers: return supplierResults.count
        case .items: return itemResults.count
        case .transactions: return transactionResults.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let category = visibleSections[section]
        let count: Int
        switch category {
        case .customers: count = customerResults.count
        case .suppliers: count = supplierResults.count
        case .items: count = itemResults.count
        case .transactions: count = transactionResults.count
        }
        return "\(category.title) (\(count))"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: afterSearchReuseID, for: indexPath) as? AfterSearchTableViewCell else {
            return UITableViewCell()
        }

        let category = visibleSections[indexPath.section]
        switch category {
        case .customers:
            let customer = customerResults[indexPath.row]
            cell.searchedTitle.text = customer.name
            cell.searchedSubTitle.text = customer.phone ?? "No phone"

        case .suppliers:
            let supplier = supplierResults[indexPath.row]
            cell.searchedTitle.text = supplier.name
            cell.searchedSubTitle.text = supplier.phone ?? "No phone"

        case .items:
            let item = itemResults[indexPath.row]
            let barcodePart = (item.barcode?.isEmpty == false) ? " • Barcode: \(item.barcode!)" : ""
            cell.searchedTitle.text = item.name
            cell.searchedSubTitle.text = "Stock: \(item.currentStock) \(item.unit)\(barcodePart)"

        case .transactions:
            let result = transactionResults[indexPath.row]
            let amountText = String(format: "₹%.2f", result.transaction.totalAmount)
            cell.searchedTitle.text = "Bill \(result.transaction.invoiceNumber) • \(amountText)"
            cell.searchedSubTitle.text = result.billItemContext
        }

        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let category = visibleSections[indexPath.section]
        switch category {
        case .items:
            let item = itemResults[indexPath.row]
            route(using: .item, payload: item)

        case .transactions:
            let transaction = transactionResults[indexPath.row].transaction
            route(using: .bill, payload: transaction)

        case .customers:
            let customer = customerResults[indexPath.row]
            route(using: .customer, payload: customer)

        case .suppliers:
            let supplier = supplierResults[indexPath.row]
            route(using: .supplier, payload: supplier)
        }
        
    }
    private func route(using route: Route, payload: Any) {
        switch route {
        case .customer:
            performSegue(withIdentifier: "customer_segue", sender: nil)
            
        case .supplier:
            performSegue(withIdentifier: "supplier_segue", sender: nil)
            
        case .item:
            guard let item = payload as? Item else { return }
            let itemProfileVC = ItemProfileTableViewController(style: .insetGrouped)
            itemProfileVC.itemID = item.id
            itemProfileVC.title = "Item Profile"
            navigationController?.pushViewController(itemProfileVC, animated: true)

        case .bill:
            guard let transaction = payload as? Transaction else { return }
            let details = transaction.toBillingDetails()
            let billVC = BillTableViewController(style: .plain)
            billVC.isReadOnly = true
            billVC.receiveBilling(details: details)
            billVC.title = "Bill"
            navigationController?.pushViewController(billVC, animated: true)
        }
    }
}

extension GlobalSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateResults(for: searchController.searchBar.text ?? "")
    }
}
