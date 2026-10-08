import UIKit
import DGCharts

class StockAnalysisViewController: UIViewController {

    /// The rankings offered by the "Items" section header dropdown.
    enum ItemsFilter: String, CaseIterable {
        case watchlisted, mostSold, mostProfitable

        var title: String {
            switch self {
            case .watchlisted: return "Watchlisted"
            case .mostSold: return "Most sold"
            case .mostProfitable: return "Most profitable"
            }
        }

        var emptyMessage: String {
            switch self {
            case .watchlisted: return "No watchlisted items yet"
            case .mostSold: return "No items sold in this period"
            case .mostProfitable: return "No profitable items in this period"
            }
        }

        var emptyIcon: String {
            switch self {
            case .watchlisted: return "star"
            case .mostSold: return "arrow.down.circle"
            case .mostProfitable: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    var selectedPeriod: ChartDataProvider.Period = .daily
    
    var chartPoints: [ChartDataProvider.ChartPoint] = []

    /// Feeds the top tile (purchases + fast/slow moving). Kept separate from
    /// `displayItems` so switching the Items filter never changes the tile's meaning.
    var purchaseItems: [ChartDataProvider.ProfitItem] = []

    /// Drives the "Items" section, already sorted per the active `itemsFilter`.
    var displayItems: [ChartDataProvider.ProfitItem] = []

    private var itemsFilter: ItemsFilter = .watchlisted
    
    let provider = ChartDataProvider.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGray6
        tableView.register(UINib(nibName: "StockAnalysisTopTileTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "StockAnalysisTopTileTableViewCell")
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                       forCellReuseIdentifier: "ItemTableViewCell")
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        reloadData()
    }
    
    func reloadData() {
            chartPoints = provider.getPurchaseChartData(period: selectedPeriod)
            purchaseItems = provider.getPurchaseItems(period: selectedPeriod)
            displayItems = itemsForFilter(itemsFilter)
            tableView.reloadData()
            
            if displayItems.isEmpty {
                tableView.setEmptyState(message: itemsFilter.emptyMessage, icon: itemsFilter.emptyIcon)
            } else {
                tableView.clearEmptyState()
            }
        }

    // MARK: - Items Filter

    /// Builds the list shown under the "Items" header for the given filter.
    ///
    /// The most-sold / most-profitable rankings come straight from `ChartDataProvider`,
    /// which already aggregates and sorts them for the selected period. The watchlist has
    /// no provider equivalent, so it is built from the item's watchlist flag and joined
    /// against the period's profit figures — watchlisted items that did not sell in the
    /// period are still listed (with zero figures) so they don't silently disappear.
    private func itemsForFilter(_ filter: ItemsFilter) -> [ChartDataProvider.ProfitItem] {
        switch filter {
        case .mostSold:
            return Array(provider.getSalesItems(period: selectedPeriod).prefix(5))

        case .mostProfitable:
            return Array(provider.getProfitItems(period: selectedPeriod).prefix(5))

        case .watchlisted:
            let watchlistedItems = ((try? AppDataModel.shared.dataModel.db.getAllItems()) ?? [])
                .filter { $0.isWatchlisted }

            var periodProfit: [UUID: ChartDataProvider.ProfitItem] = [:]
            for entry in provider.getProfitItems(period: selectedPeriod) {
                if let id = entry.itemID {
                    periodProfit[id] = entry
                }
            }

            return watchlistedItems
                .map { item -> ChartDataProvider.ProfitItem in
                    periodProfit[item.id] ?? ChartDataProvider.ProfitItem(
                        itemID: item.id,
                        name: item.name,
                        quantity: 0,
                        costPrice: 0,
                        sellingPrice: 0
                    )
                }
                .sorted { $0.totalProfit > $1.totalProfit }
        }
    }

    private func applyFilter(_ filter: ItemsFilter) {
        guard itemsFilter != filter else { return }
        itemsFilter = filter
        reloadData()
    }

    private func filterMenu() -> UIMenu {
        // `.on` renders the system checkmark for the active option, so no custom icon.
        let actions = ItemsFilter.allCases.map { option in
            UIAction(
                title: option.title,
                state: option == itemsFilter ? .on : .off
            ) { [weak self] _ in
                self?.applyFilter(option)
            }
        }
        return UIMenu(children: actions)
    }

    @IBAction func segmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: selectedPeriod = .daily
        case 1: selectedPeriod = .monthly
        case 2: selectedPeriod = .quarterly
        case 3: selectedPeriod = .yearly
        default: selectedPeriod = .daily
        }
        reloadData()
    }
    
    
}
extension StockAnalysisViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

        if section == 0 {
            return 1
        }

        return displayItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        switch indexPath.section {

        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "StockAnalysisTopTileTableViewCell",for: indexPath) as! StockAnalysisTopTileTableViewCell

            cell.configure(
                chartPoints: chartPoints,
                items: purchaseItems
            )

            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "ItemTableViewCell",
                for: indexPath
            ) as! ItemTableViewCell

            let item = displayItems[indexPath.row]

            // Reuses the shared cell's configure helper so the row matches every other
            // item list in the app. The trailing metric follows the active ranking:
            // profit for both profit-ordered modes, revenue for most-sold.
            let metricValue: Double
            switch itemsFilter {
            case .mostSold:
                metricValue = item.sellingPrice * item.quantity
            case .watchlisted, .mostProfitable:
                metricValue = item.totalProfit
            }

            cell.configure(
                itemName: item.name,
                qty: item.quantity.cleanString,
                price: String(format: "₹%.2f", metricValue)
            )

            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == displayItems.count - 1
            
            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
            return cell
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 1 { return 44 }
        return 0
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = UIView()
        
        if section == 1 {
            let label = UILabel()
            label.text = "Items"
            label.font = .systemFont(ofSize: 20, weight: .bold)
            label.textColor = .label
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)

            // Dropdown for switching the ranking. Doubles as the current-selection
            // indicator by showing the active filter's name.
            let filterButton = UIButton(type: .system)
            filterButton.setTitle(itemsFilter.title, for: .normal)
            filterButton.setImage(UIImage(systemName: "chevron.up.chevron.down"), for: .normal)
            filterButton.tintColor = UIColor(named: "Lime Moss") ?? .systemGreen
            filterButton.setTitleColor(UIColor(named: "Lime Moss") ?? .systemGreen, for: .normal)
            filterButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            filterButton.titleLabel?.lineBreakMode = .byTruncatingTail
            filterButton.semanticContentAttribute = .forceRightToLeft
            filterButton.showsMenuAsPrimaryAction = true
            filterButton.menu = filterMenu()
            filterButton.accessibilityLabel = "Filter items, currently \(itemsFilter.title)"
            filterButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(filterButton)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),

                filterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                filterButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                filterButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8)
            ])
        }
        return view
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        let item = displayItems[indexPath.row]
        performSegue(withIdentifier: "item_profile", sender: item)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_profile",
           let itemProfileVC = segue.destination as? ItemProfileTableViewController,
           let profitItem = sender as? ChartDataProvider.ProfitItem {
            itemProfileVC.itemID = profitItem.itemID
        }
    }
}
