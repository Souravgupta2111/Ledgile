import UIKit
import DGCharts

class StockAnalysisViewController: UIViewController {

    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    var selectedPeriod: ChartDataProvider.Period = .daily
    
    var chartPoints: [ChartDataProvider.ChartPoint] = []
    var salesItems: [ChartDataProvider.ProfitItem] = []
    
    let provider = ChartDataProvider.shared
    
    var items: [Item] = []
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
            chartPoints = provider.getItemsSoldChartData(period: selectedPeriod)

            salesItems = provider.getSalesItems(period: selectedPeriod)

            tableView.reloadData()
        }

    @IBAction func segmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: selectedPeriod = .daily
        case 1: selectedPeriod = .weekly
        case 2: selectedPeriod = .monthly
        case 3: selectedPeriod = .yearly
        default: selectedPeriod = .daily
        }
        reloadData()
    }
    
    @IBAction func downloadTapped(_ sender: UIBarButtonItem) {
        
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

        return salesItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        switch indexPath.section {

        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "StockAnalysisTopTileTableViewCell",for: indexPath) as! StockAnalysisTopTileTableViewCell

            cell.configure(
                chartPoints: chartPoints,
                items: salesItems
            )

            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "ItemTableViewCell",
                for: indexPath
            ) as! ItemTableViewCell

            let item = salesItems[indexPath.row]

            cell.itemNameLabel.text = item.name
            cell.priceLabel.text = "Sold: \(item.quantity)"
            cell.quantityLabel.text = "\(item.quantity) x ₹\(item.sellingPrice) = ₹\(Double(item.quantity) * item.sellingPrice)"
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == salesItems.count - 1
            
            cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)
            return cell
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 1 { return 30 }
        return 0
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = UIView()
        
        if section == 1 {
            let label = UILabel()
            label.text = "Items Sold"
            label.font = .systemFont(ofSize: 20, weight: .bold)
            label.textColor = .label
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
            ])
        }
        return view
    }
}
