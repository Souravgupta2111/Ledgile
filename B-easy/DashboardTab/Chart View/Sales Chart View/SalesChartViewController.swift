import UIKit
import DGCharts

class SalesChartViewController: UIViewController {
    
    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    
    var selectedPeriod: ChartDataProvider.Period = .daily
    let provider = ChartDataProvider.shared
    var chartPoints: [ChartDataProvider.ChartPoint] = []
    var salesItems: [ChartDataProvider.ProfitItem] = []
    var selectedBarIndex: Int? = nil
    
    @IBAction func downloadButtonTapped(_ sender: UIButton) {
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Sales"
        view.backgroundColor = .systemGroupedBackground
        
        tableView.backgroundColor = .systemGray6
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none

        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil), forCellReuseIdentifier: "ItemTableViewCell")
        tableView.register(UINib(nibName: "SalesByItemTopTileTableViewCell", bundle: nil), forCellReuseIdentifier: "SalesByItemTopTileTableViewCell")
        
        tableView.rowHeight = UITableView.automaticDimension
        
        segment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        
        reloadData()
    }
    
    @objc func segmentChanged(_ sender: UISegmentedControl) {
        selectedBarIndex = nil
        switch sender.selectedSegmentIndex {
        case 0: selectedPeriod = .daily
        case 1: selectedPeriod = .monthly
        case 2: selectedPeriod = .quarterly
        case 3: selectedPeriod = .yearly
        default: selectedPeriod = .daily
        }
        reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    func reloadData() {
        // Load chart data
        chartPoints = provider.getRevenueChartData(period: selectedPeriod)
        salesItems = provider.getSalesItems(period: selectedPeriod)
        tableView.reloadData()
        
        if salesItems.isEmpty {
            tableView.setEmptyState(message: "No sales data available", icon: "chart.bar.xaxis")
        } else {
            tableView.clearEmptyState()
        }
    }
    
    func topSellingItem() -> String {
        salesItems.max(by: { ($0.sellingPrice * $0.quantity) < ($1.sellingPrice * $1.quantity) })?.name ?? " "
    }
    
    func totalItemsSold() -> Int {
        salesItems.count
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_profile",
           let itemProfileVC = segue.destination as? ItemProfileTableViewController,
           let selectedItem = sender as? ChartDataProvider.ProfitItem {
            itemProfileVC.itemID = selectedItem.itemID
        }
    }
}

extension SalesChartViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        return min(salesItems.count, 10)
    }
    

    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "SalesByItemTopTileTableViewCell",
                for: indexPath
            ) as? SalesByItemTopTileTableViewCell else {
                return UITableViewCell()
            }
            
            cell.delegate = self

            let totalAmount = chartPoints.reduce(0) { $0 + $1.value }
            let growthText = provider.periodGrowth(for: selectedPeriod, metric: .revenue)
            let periodLabel = provider.comparisonLabel(for: selectedPeriod)

            let barLabels = chartPoints.map { $0.label }
            let barValues = chartPoints.map { $0.value }

            let items: [ChartDataProvider.ProfitItem]
            let subtitle: String
            
            if let index = selectedBarIndex {
                items = provider.getSalesItems(for: selectedPeriod, atIndex: index, totalBars: chartPoints.count)
                subtitle = chartPoints[index].label
            } else {
                items = provider.getSalesItems(period: selectedPeriod)
                switch selectedPeriod {
                case .daily: subtitle = "This Week"
                case .monthly: subtitle = "Last 12 Months"
                case .quarterly: subtitle = "This Year"
                case .yearly: subtitle = "Last 5 Years"
                }
            }

            let currentItemsSold = items.count
            let currentTopItem = items.max(by: { ($0.sellingPrice * $0.quantity) < ($1.sellingPrice * $1.quantity) })?.name ?? "-"

            let bottomChartData = provider.getItemsSoldChartData(period: .daily)
            let bottomBarLabels = bottomChartData.map { $0.label }
            let bottomBarValues = bottomChartData.map { $0.value }

            cell.configure(
                totalAmount: totalAmount,
                growthText: "\(growthText)  \(periodLabel)",
                itemsSold: currentItemsSold,
                topItem: currentTopItem,
                subtitle: subtitle,
                lineChartPoints: chartPoints,
                barChartValues: bottomBarValues,
                barChartLabels: bottomBarLabels,
                period: selectedPeriod
            )

            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemTableViewCell", for: indexPath) as! ItemTableViewCell
            let displayedCount = min(salesItems.count, 10)
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == displayedCount - 1

            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)

            let item = salesItems[indexPath.row]
            cell.itemNameLabel.text = item.name
            cell.quantityLabel.text = "Sold: \(item.quantity) | Cost: ₹\(Int(item.costPrice))"
            let total = item.quantity * item.sellingPrice
            cell.priceLabel.text = "₹\(Int(total))"
                    
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 1 {
            let headerView = UIView()
            headerView.backgroundColor = .systemGray6
            
            let label = UILabel()
            label.text = "Items"
            label.textColor = .blackWhite
            label.font = UIFont.boldSystemFont(ofSize: 21)
            label.textAlignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
    
            headerView.addSubview(label)
            
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: -8),
                label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
            ])
            
            return headerView
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 1 {
            return 40
        }
        return 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        let item = salesItems[indexPath.row]
        performSegue(withIdentifier: "item_profile", sender: item)
    }
}

extension SalesChartViewController: SalesByItemTopTileDelegate {
    func didSelectChartBar(at index: Int) {
        selectedBarIndex = index
        let items = provider.getSalesItems(for: selectedPeriod, atIndex: index, totalBars: chartPoints.count)
        let subtitle = chartPoints[index].label
        let currentItemsSold = items.count
        let currentTopItem = items.max(by: { ($0.sellingPrice * $0.quantity) < ($1.sellingPrice * $1.quantity) })?.name ?? "-"
        
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? SalesByItemTopTileTableViewCell {
            cell.updateTopItemDetails(itemsSold: currentItemsSold, topItemName: currentTopItem, subtitle: subtitle)
        }
    }
    
    func didDeselectChartBar() {
        selectedBarIndex = nil
        let items = provider.getSalesItems(period: selectedPeriod)
        let subtitle: String
        switch selectedPeriod {
        case .daily: subtitle = "This Week"
        case .monthly: subtitle = "Last 12 Months"
        case .quarterly: subtitle = "This Year"
        case .yearly: subtitle = "Last 5 Years"
        }
        
        let currentItemsSold = items.count
        let currentTopItem = items.max(by: { ($0.sellingPrice * $0.quantity) < ($1.sellingPrice * $1.quantity) })?.name ?? "-"
        
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? SalesByItemTopTileTableViewCell {
            cell.updateTopItemDetails(itemsSold: currentItemsSold, topItemName: currentTopItem, subtitle: subtitle)
        }
    }
}
