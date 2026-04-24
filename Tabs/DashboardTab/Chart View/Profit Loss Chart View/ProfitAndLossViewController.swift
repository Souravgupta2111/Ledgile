import UIKit

class ProfitAndLossViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var segment: UISegmentedControl!
    
    var selectedPeriod: ChartDataProvider.Period = .daily
    var chartPoints: [ChartDataProvider.ChartPoint] = []
    var items: [ChartDataProvider.ProfitItem] = []
    let provider = ChartDataProvider.shared

    
    @IBAction func downloadButtonTapped(_ sender: UIButton) {
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGray6
        tableView.register(UINib(nibName: "ProfitAndLossTopTileTableViewCell", bundle: nil), forCellReuseIdentifier: "ProfitAndLossTopTileTableViewCell")
        tableView.register(UINib(nibName: "ItemTableViewCell", bundle: nil), forCellReuseIdentifier: "ItemTableViewCell")
        
        segment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        
        reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }
    
    func reloadData() {
        chartPoints = provider.getProfitChartData(period: selectedPeriod)
        items = provider.getProfitItems(period: selectedPeriod)
        tableView.reloadData()
    }

    func calculateGrowth() -> String {
        let currentTotal = chartPoints.reduce(0) { $0 + $1.value }
        let previousPoints = provider.getComparisonProfitChartData(period: selectedPeriod)
        let previousTotal = previousPoints.reduce(0) { $0 + $1.value }

        if previousTotal == 0 {
            return currentTotal > 0 ? "+100%" : "0%"
        }
        let growth = ((currentTotal - previousTotal) / previousTotal) * 100
        let sign = growth >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", growth))%"
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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_profile",
           let itemProfileVC = segue.destination as? ItemProfileTableViewController,
           let selectedItem = sender as? ChartDataProvider.ProfitItem {
            itemProfileVC.itemID = selectedItem.itemID
        }
    }
}

extension ProfitAndLossViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return items.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "ProfitAndLossTopTileTableViewCell", for: indexPath) as? ProfitAndLossTopTileTableViewCell else {
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

            cell.configure(
                totalAmount: totalAmount,
                growthText: "\(growthText)  \(periodLabel)",
                lineChartPoints: chartPoints
            )
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "ItemTableViewCell", for: indexPath) as? ItemTableViewCell else {
                return UITableViewCell()
            }
            
            let item = items[indexPath.row]
            cell.configure(
                itemName: item.name,
                qty: "\(item.quantity)",
                price: "₹\(String(format: "%.2f", item.totalProfit))"
            )
            
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == items.count - 1
            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
            cell.separatorView.isHidden = isLast
            
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 1 {
            let headerView = UIView()
            headerView.backgroundColor = .systemGray6
            
            let label = UILabel()
            label.text = "Profit By Item"
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
        let item = items[indexPath.row]
        performSegue(withIdentifier: "item_profile", sender: item)
    }
}
