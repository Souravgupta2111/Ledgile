import UIKit
import DGCharts

final class CreditChartTopTableViewCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let amountLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let lineChartView = LineChartView()

    private let getTitleLabel = UILabel()
    private let getHolderLabel = UILabel()
    private let getChevronButton = UIButton(type: .system)

    private let giveTitleLabel = UILabel()
    private let giveHolderLabel = UILabel()
    private let giveChevronButton = UIButton(type: .system)

    var onCustomerChevronTapped: (() -> Void)?
    var onSupplierChevronTapped: (() -> Void)?

    private var didSetup = false

    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
        setupUIIfNeeded()
        setupCharts()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onCustomerChevronTapped = nil
        onSupplierChevronTapped = nil
        setupUIIfNeeded()
    }

    func configure(
        totalExposure: Double,
        customerSeries: [Double],
        supplierSeries: [Double],
        chartLabels: [String],
        topCustomerHolder: String,
        topSupplierHolder: String
    ) {
        setupUIIfNeeded()

        amountLabel.text = "₹\(Int(totalExposure))"
        subtitleLabel.text = "Green: Customer • Red: Supplier"

        getHolderLabel.text = topCustomerHolder.isEmpty ? "—" : topCustomerHolder
        giveHolderLabel.text = topSupplierHolder.isEmpty ? "—" : topSupplierHolder

        let customerEntries = customerSeries.enumerated().map {
            ChartDataEntry(x: Double($0.offset), y: $0.element)
        }
        let supplierEntries = supplierSeries.enumerated().map {
            ChartDataEntry(x: Double($0.offset), y: $0.element)
        }

        let customerSet = LineChartDataSet(entries: customerEntries, label: "Customer")
        customerSet.colors = [UIColor(named: "Lime Moss")!]
        customerSet.circleColors = [UIColor(named: "Lime Moss")!]
        customerSet.circleRadius = 2.5
        customerSet.lineWidth = 2
        customerSet.drawValuesEnabled = false
        customerSet.mode = .linear

        let supplierSet = LineChartDataSet(entries: supplierEntries, label: "Supplier")
        supplierSet.colors = [.systemRed]
        supplierSet.circleColors = [.systemRed]
        supplierSet.circleRadius = 2.5
        supplierSet.lineWidth = 2
        supplierSet.drawValuesEnabled = false
        supplierSet.mode = .linear

        let lineData = LineChartData(dataSets: [customerSet, supplierSet])
        lineChartView.data = lineData
        lineChartView.xAxis.valueFormatter = IndexAxisValueFormatter(values: chartLabels)
        lineChartView.xAxis.granularity = 1
        lineChartView.xAxis.labelCount = max(chartLabels.count, 1)
        lineChartView.xAxis.forceLabelsEnabled = true
        lineChartView.notifyDataSetChanged()
    }

    private func setupCharts() {
        lineChartView.rightAxis.enabled = false
        lineChartView.chartDescription.enabled = false
        lineChartView.xAxis.labelPosition = .bottom
        lineChartView.leftAxis.enabled = true
        lineChartView.xAxis.drawGridLinesEnabled = true
        lineChartView.xAxis.labelTextColor = .white
        lineChartView.dragEnabled = false
        lineChartView.pinchZoomEnabled = false
        lineChartView.scaleXEnabled = false
        lineChartView.scaleYEnabled = false

        lineChartView.leftAxis.axisMinimum = 0
        lineChartView.leftAxis.labelTextColor = .white
        lineChartView.leftAxis.drawGridLinesEnabled = true
        lineChartView.leftAxis.drawAxisLineEnabled = true

        lineChartView.legend.enabled = true
        lineChartView.legend.textColor = .white
        lineChartView.legend.form = .line
        lineChartView.legend.horizontalAlignment = .right
        lineChartView.legend.verticalAlignment = .top
        lineChartView.legend.orientation = .horizontal
        lineChartView.legend.drawInside = true
    }

    private func setupUIIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        contentView.backgroundColor = .systemGray6

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGray6
        contentView.addSubview(container)

        let topCard = UIView()
        topCard.translatesAutoresizingMaskIntoConstraints = false
        topCard.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.78)
        topCard.layer.cornerRadius = 24
        topCard.clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Credit Analysis"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 24, weight: .bold)
        amountLabel.textColor = .white

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = .white.withAlphaComponent(0.95)
        subtitleLabel.textAlignment = .right

        lineChartView.translatesAutoresizingMaskIntoConstraints = false
        lineChartView.backgroundColor = .clear

        topCard.addSubview(titleLabel)
        topCard.addSubview(amountLabel)
        topCard.addSubview(subtitleLabel)
        topCard.addSubview(lineChartView)

        let getCard = UIView()
        getCard.translatesAutoresizingMaskIntoConstraints = false
        getCard.backgroundColor = .systemBackground
        getCard.layer.cornerRadius = 20
        getCard.clipsToBounds = true

        getTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        getTitleLabel.text = "You Will Get"
        getTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        getHolderLabel.translatesAutoresizingMaskIntoConstraints = false
        getHolderLabel.font = .systemFont(ofSize: 20, weight: .bold)
        getHolderLabel.textColor = UIColor(named: "Lime Moss")!
        getHolderLabel.numberOfLines = 2

        styleChevronButton(getChevronButton)
        getChevronButton.translatesAutoresizingMaskIntoConstraints = false
        getChevronButton.addTarget(self, action: #selector(customerChevronTapped), for: .touchUpInside)

        getCard.addSubview(getTitleLabel)
        getCard.addSubview(getHolderLabel)
        getCard.addSubview(getChevronButton)

        let giveCard = UIView()
        giveCard.translatesAutoresizingMaskIntoConstraints = false
        giveCard.backgroundColor = .systemBackground
        giveCard.layer.cornerRadius = 20
        giveCard.clipsToBounds = true

        giveTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        giveTitleLabel.text = "You Will Give"
        giveTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        giveHolderLabel.translatesAutoresizingMaskIntoConstraints = false
        giveHolderLabel.font = .systemFont(ofSize: 20, weight: .bold)
        giveHolderLabel.textColor = .systemRed
        giveHolderLabel.numberOfLines = 2

        styleChevronButton(giveChevronButton)
        giveChevronButton.translatesAutoresizingMaskIntoConstraints = false
        giveChevronButton.addTarget(self, action: #selector(supplierChevronTapped), for: .touchUpInside)

        giveCard.addSubview(giveTitleLabel)
        giveCard.addSubview(giveHolderLabel)
        giveCard.addSubview(giveChevronButton)

        container.addSubview(topCard)
        container.addSubview(getCard)
        container.addSubview(giveCard)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            topCard.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            topCard.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            topCard.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            topCard.heightAnchor.constraint(equalToConstant: 280),

            titleLabel.topAnchor.constraint(equalTo: topCard.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: topCard.leadingAnchor, constant: 16),

            amountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            amountLabel.leadingAnchor.constraint(equalTo: topCard.leadingAnchor, constant: 16),

            subtitleLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: topCard.trailingAnchor, constant: -16),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            lineChartView.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 10),
            lineChartView.leadingAnchor.constraint(equalTo: topCard.leadingAnchor, constant: 10),
            lineChartView.trailingAnchor.constraint(equalTo: topCard.trailingAnchor, constant: -10),
            lineChartView.bottomAnchor.constraint(equalTo: topCard.bottomAnchor, constant: -10),

            getCard.topAnchor.constraint(equalTo: topCard.bottomAnchor, constant: 12),
            getCard.leadingAnchor.constraint(equalTo: topCard.leadingAnchor),
            getCard.widthAnchor.constraint(equalTo: giveCard.widthAnchor),
            getCard.heightAnchor.constraint(equalToConstant: 130),

            giveCard.topAnchor.constraint(equalTo: topCard.bottomAnchor, constant: 12),
            giveCard.leadingAnchor.constraint(equalTo: getCard.trailingAnchor, constant: 12),
            giveCard.trailingAnchor.constraint(equalTo: topCard.trailingAnchor),
            giveCard.heightAnchor.constraint(equalToConstant: 130),

            getTitleLabel.topAnchor.constraint(equalTo: getCard.topAnchor, constant: 12),
            getTitleLabel.leadingAnchor.constraint(equalTo: getCard.leadingAnchor, constant: 14),

            getChevronButton.trailingAnchor.constraint(equalTo: getCard.trailingAnchor, constant: -10),
            getChevronButton.centerYAnchor.constraint(equalTo: getTitleLabel.centerYAnchor),

            getHolderLabel.topAnchor.constraint(equalTo: getTitleLabel.bottomAnchor, constant: 8),
            getHolderLabel.leadingAnchor.constraint(equalTo: getCard.leadingAnchor, constant: 14),
            getHolderLabel.trailingAnchor.constraint(equalTo: getCard.trailingAnchor, constant: -12),

            giveTitleLabel.topAnchor.constraint(equalTo: giveCard.topAnchor, constant: 12),
            giveTitleLabel.leadingAnchor.constraint(equalTo: giveCard.leadingAnchor, constant: 14),

            giveChevronButton.trailingAnchor.constraint(equalTo: giveCard.trailingAnchor, constant: -10),
            giveChevronButton.centerYAnchor.constraint(equalTo: giveTitleLabel.centerYAnchor),

            giveHolderLabel.topAnchor.constraint(equalTo: giveTitleLabel.bottomAnchor, constant: 8),
            giveHolderLabel.leadingAnchor.constraint(equalTo: giveCard.leadingAnchor, constant: 14),
            giveHolderLabel.trailingAnchor.constraint(equalTo: giveCard.trailingAnchor, constant: -12),

            container.bottomAnchor.constraint(equalTo: getCard.bottomAnchor, constant: 8)
        ])
    }

    private func styleChevronButton(_ button: UIButton) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.right")
        config.baseForegroundColor = .secondaryLabel
        button.configuration = config
    }

    @objc private func customerChevronTapped() {
        onCustomerChevronTapped?()
    }

    @objc private func supplierChevronTapped() {
        onSupplierChevronTapped?()
    }
}
