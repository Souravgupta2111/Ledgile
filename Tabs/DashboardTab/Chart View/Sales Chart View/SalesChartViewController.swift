import UIKit
import DGCharts

class SalesChartViewController: UIViewController {
    
    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    
    var selectedPeriod: ChartDataProvider.Period = .daily
    let provider = ChartDataProvider.shared
    var chartPoints: [ChartDataProvider.ChartPoint] = []
    var salesItems: [ChartDataProvider.ProfitItem] = []
    
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
        switch sender.selectedSegmentIndex {
        case 0: selectedPeriod = .daily
        case 1: selectedPeriod = .weekly
        case 2: selectedPeriod = .monthly
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
    }
    
    func calculateGrowth() -> String {
        let currentTotal = chartPoints.reduce(0) { $0 + $1.value }
        let previousPoints = provider.getComparisonRevenueChartData(period: selectedPeriod)
        let previousTotal = previousPoints.reduce(0) { $0 + $1.value }
        
        if previousTotal == 0 {
            return currentTotal > 0 ? "+100%" : "0%"
        }
        let growth = ((currentTotal - previousTotal) / previousTotal) * 100
        let sign = growth >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", growth))%"
    }
    
    func topSellingItem() -> String {
        salesItems.max(by: { ($0.sellingPrice * Double($0.quantity)) < ($1.sellingPrice * Double($1.quantity)) })?.name ?? "—"
    }
    
    func totalItemsSold() -> Int {
        salesItems.reduce(0) { $0 + $1.quantity }
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

            let totalAmount = chartPoints.reduce(0) { $0 + $1.value }
            let growthText = calculateGrowth()
            let periodLabel: String
            switch selectedPeriod {
            case .daily:   periodLabel = "vs prev 7 days"
            case .weekly:  periodLabel = "vs prev 7 weeks"
            case .monthly: periodLabel = "vs prev 7 months"
            case .yearly:  periodLabel = "vs prev 7 years"
            }

            let barLabels = chartPoints.map { $0.label }
            let barValues = chartPoints.map { $0.value }

            // Items Sold & Top Item always use today's data
            let todaySalesItems = provider.getSalesItems(period: .daily)
            let todayItemsSold = todaySalesItems.reduce(0) { $0 + $1.quantity }
            let todayTopItem = todaySalesItems.max(by: { ($0.sellingPrice * Double($0.quantity)) < ($1.sellingPrice * Double($1.quantity)) })?.name ?? "—"

            // Bottom bar chart always shows daily (last 7 days) items sold
            let dailyItemsChartData = provider.getItemsSoldChartData(period: .daily)
            let bottomBarLabels = dailyItemsChartData.map { $0.label }
            let bottomBarValues = dailyItemsChartData.map { $0.value }

            cell.configure(
                totalAmount: totalAmount,
                growthText: "\(growthText)  \(periodLabel)",
                itemsSold: todayItemsSold,
                topItem: todayTopItem,
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
            let total = Double(item.quantity) * item.sellingPrice
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
