import UIKit

class CreditChartViewController: UIViewController {

    @IBOutlet weak var creditTable: UITableView!
    @IBOutlet weak var durationSegment: UISegmentedControl!

    private enum Period {
        case daily
        case weekly
        case monthly
        case yearly
    }

    private struct CreditHolderRow {
        let name: String
        let amount: Double
        let isReceivable: Bool
    }

    private struct IntervalBucket {
        let start: Date
        let end: Date
        let label: String
    }

    private var selectedPeriod: Period = .daily
    private var rows: [CreditHolderRow] = []

    private var receivableTotal: Double = 0
    private var payableTotal: Double = 0

    private var customerSeries: [Double] = []
    private var supplierSeries: [Double] = []
    private var bucketLabels: [String] = []

    private var topCustomerHolderName: String = ""
    private var topSupplierHolderName: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Credit Analysis"
        view.backgroundColor = .systemGroupedBackground

        creditTable.backgroundColor = .systemGray6
        creditTable.dataSource = self
        creditTable.delegate = self
        creditTable.separatorStyle = .none
        creditTable.rowHeight = UITableView.automaticDimension

        creditTable.register(UINib(nibName: "CreditChartTopTableViewCell", bundle: nil),
                             forCellReuseIdentifier: "CreditChartTopTableViewCell")
        creditTable.register(UINib(nibName: "ItemTableViewCell", bundle: nil),
                             forCellReuseIdentifier: "ItemTableViewCell")

        durationSegment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)

        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: selectedPeriod = .daily
        case 1: selectedPeriod = .weekly
        case 2: selectedPeriod = .monthly
        case 3: selectedPeriod = .yearly
        default: selectedPeriod = .daily
        }
        reloadData()
    }

    private func reloadData() {
        let store = CreditStore.shared

        receivableTotal = store.getTotalReceivable()
        payableTotal = store.getTotalPayable()

        let customers = store.getAllCustomers()
        let customerRows: [CreditHolderRow] = customers.compactMap { customer in
            guard customer.netBalance > 0 else { return nil }
            return CreditHolderRow(
                name: customer.name,
                amount: customer.netBalance,
                isReceivable: true
            )
        }

        let suppliers = store.getAllSuppliers()
        let supplierRows: [CreditHolderRow] = suppliers.compactMap { supplier in
            guard supplier.netBalance > 0 else { return nil }
            return CreditHolderRow(
                name: supplier.name,
                amount: supplier.netBalance,
                isReceivable: false
            )
        }

        rows = (customerRows + supplierRows).sorted { $0.amount > $1.amount }
        topCustomerHolderName = customerRows.max(by: { $0.amount < $1.amount })?.name ?? ""
        topSupplierHolderName = supplierRows.max(by: { $0.amount < $1.amount })?.name ?? ""

        let buckets = buildBuckets(period: selectedPeriod, count: 7)
        bucketLabels = buckets.map { $0.label }

        var receivableDelta = Array(repeating: 0.0, count: buckets.count)
        var payableDelta = Array(repeating: 0.0, count: buckets.count)

        for customer in customers {
            let payments = store.getPayments(forCustomer: customer.id)
            for payment in payments {
                guard let idx = bucketIndex(for: payment.date, in: buckets) else { continue }
                switch payment.type {
                case .paid:
                    receivableDelta[idx] += payment.amount
                case .received:
                    receivableDelta[idx] -= payment.amount
                }
            }
        }

        for supplier in suppliers {
            let payments = store.getPayments(forSupplier: supplier.id)
            for payment in payments {
                guard let idx = bucketIndex(for: payment.date, in: buckets) else { continue }
                switch payment.type {
                case .received:
                    payableDelta[idx] += payment.amount
                case .paid:
                    payableDelta[idx] -= payment.amount
                }
            }
        }

        customerSeries = cumulativeSeries(from: receivableDelta)
        supplierSeries = cumulativeSeries(from: payableDelta)

        creditTable.reloadData()
    }

    private func bucketIndex(for date: Date, in buckets: [IntervalBucket]) -> Int? {
        for (index, bucket) in buckets.enumerated() {
            if date >= bucket.start && date < bucket.end {
                return index
            }
        }
        return nil
    }

    private func cumulativeSeries(from deltas: [Double]) -> [Double] {
        var running = 0.0
        return deltas.map { delta in
            running = max(0, running + delta)
            return running
        }
    }

    private func buildBuckets(period: Period, count: Int) -> [IntervalBucket] {
        let calendar = Calendar.current
        let now = Date()

        func startOfPeriod(_ date: Date) -> Date {
            switch period {
            case .daily:
                return calendar.startOfDay(for: date)
            case .weekly:
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            case .monthly:
                let components = calendar.dateComponents([.year, .month], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            case .yearly:
                let components = calendar.dateComponents([.year], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            }
        }

        func addPeriod(_ date: Date, value: Int) -> Date {
            switch period {
            case .daily:
                return calendar.date(byAdding: .day, value: value, to: date) ?? date
            case .weekly:
                return calendar.date(byAdding: .weekOfYear, value: value, to: date) ?? date
            case .monthly:
                return calendar.date(byAdding: .month, value: value, to: date) ?? date
            case .yearly:
                return calendar.date(byAdding: .year, value: value, to: date) ?? date
            }
        }

        func label(for start: Date) -> String {
            let formatter = DateFormatter()
            switch period {
            case .daily:
                formatter.dateFormat = "E"
            case .weekly:
                formatter.dateFormat = "dd MMM"
            case .monthly:
                formatter.dateFormat = "MMM"
            case .yearly:
                formatter.dateFormat = "yyyy"
            }
            return formatter.string(from: start)
        }

        let currentStart = startOfPeriod(now)

        return (0..<count).map { idx in
            let shift = idx - (count - 1)
            let start = addPeriod(currentStart, value: shift)
            let end = addPeriod(start, value: 1)
            return IntervalBucket(start: start, end: end, label: label(for: start))
        }
    }
}

extension CreditChartViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        return min(rows.count, 20)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "CreditChartTopTableViewCell",
                for: indexPath
            ) as? CreditChartTopTableViewCell else {
                return UITableViewCell()
            }

            let totalExposure = receivableTotal + payableTotal
            cell.configure(
                totalExposure: totalExposure,
                customerSeries: customerSeries,
                supplierSeries: supplierSeries,
                chartLabels: bucketLabels,
                topCustomerHolder: topCustomerHolderName,
                topSupplierHolder: topSupplierHolderName
            )
            cell.onCustomerChevronTapped = { [weak self] in
                self?.performSegue(withIdentifier: "credit_customer", sender: nil)
            }
            cell.onSupplierChevronTapped = { [weak self] in
                self?.performSegue(withIdentifier: "credit_supplier", sender: nil)
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "ItemTableViewCell",
            for: indexPath
        ) as? ItemTableViewCell else {
            return UITableViewCell()
        }

        let displayedCount = min(rows.count, 20)
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == displayedCount - 1
        cell.applySectionCornerMask(isFirst: isFirst, isLast: isLast)

        let row = rows[indexPath.row]
        cell.itemNameLabel.text = row.name
        cell.priceLabel.text = "₹\(Int(row.amount))"
        cell.priceLabel.textColor = row.isReceivable ? UIColor(named: "Lime Moss")! : .systemRed
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }

        let headerView = UIView()
        headerView.backgroundColor = .systemGray6

        let label = UILabel()
        label.text = "Credit Holders"
        label.textColor = .black
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

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 1 ? 40 : 0
    }
}
