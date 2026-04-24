import UIKit
import Foundation
import DGCharts

class DashboardTopTileTableViewCell: UITableViewCell {
    protocol TopTileTableViewCellDelegate: AnyObject {
        func topTileCellDidTapRevenue(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapInvestment(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapManualSalesEntry(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapVoiceSalesEntry(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapManualPurchaseEntry(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapScanPurchaseEntry(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapGet(_ cell: DashboardTopTileTableViewCell)
        func topTileCellDidTapPay(_ cell: DashboardTopTileTableViewCell)
    }
    
    var revenueTapped: (() -> Void)?
    var investmentTapped: (() -> Void)?
    var lowStockTapped: (() -> Void)?
    var manualSalesTapped: (() -> Void)?
    var voiceSalesTapped: (() -> Void)?
    var manualPurchaseTapped: (() -> Void)?
    var objectPurchaseTapped: (() -> Void)?
    var getTapped: (() -> Void)?
    var payTapped: (() -> Void)?
    var expiryTapped: (() -> Void)?

    @IBAction func revenueButtonTapped(_ sender: UIButton) { revenueTapped?() }
    @IBAction func investmentButtonTapped(_ sender: UIButton) { investmentTapped?() }
    @IBAction func lowStockButtonTapped(_ sender: UIButton) { lowStockTapped?() }
    @IBAction func expiryButtonTapped(_ sender: UIButton) { expiryTapped?() }
    @IBAction func manualSalesEntry(_ sender: UIButton) { manualSalesTapped?() }
    @IBAction func voiceSalesEntry(_ sender: UIButton) { voiceSalesTapped?() }
    @IBAction func manualPurchaseEntry(_ sender: UIButton) { manualPurchaseTapped?() }
    @IBAction func objectPurchaseEntry(_ sender: UIButton) {
        objectPurchaseTapped?()
        delegate?.topTileCellDidTapScanPurchaseEntry(self)
    }
    @IBAction func youWillGetTapped(_ sender: UIButton) { getTapped?() }
    @IBAction func youWillPay(_ sender: UIButton) { payTapped?() }
    
    weak var delegate: TopTileTableViewCellDelegate?
    let chartProvider = ChartDataProvider.shared
    var dashboardData: [ChartDataProvider.WeekDayData] = []
    
    enum TopTileTab { case revenue, investment }
    var activeTab: TopTileTab = .revenue
    
    var storedRevenueAmount: String = ""
    var storedInvestmentAmount: String = ""
    
    @IBOutlet weak var segmentedCardBackground: SegmentedCardBackgroundView!
    @IBOutlet weak var youWillPayLabel: UILabel!
    @IBOutlet weak var youWillGetLabel: UILabel!
    @IBOutlet weak var restockCountLabel: UILabel!
    @IBOutlet weak var expiryCountLabel: UILabel!
    @IBOutlet var lowStockButton: UIButton!
    @IBOutlet var expiryAlertButton: UIButton!
    
    // Left side (Revenue text or Revenue pill)
    private var leftPillButton: UIButton!
    private var leftTitleLabel: UILabel!
    private var leftChevron: UIButton!
    private var leftSubtitleLabel: UILabel!
    private var leftAmountLabel: UILabel!
    
    // Right side (Investment text or Investment pill)
    private var rightPillButton: UIButton!
    private var rightTitleLabel: UILabel!
    private var rightChevron: UIButton!
    private var rightSubtitleLabel: UILabel!
    private var rightAmountLabel: UILabel!
    
    private var chartView: BarChartView!
    private var cardViewsBuilt = false
    
    var weeklyData: [String: WeekData] = [:]
    let orderedDays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    struct WeekData { var revenue: Double; var investment: Double }

    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
        backgroundColor = .clear
        buildCardViews()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    private func buildCardViews() {
        guard !cardViewsBuilt else { return }
        cardViewsBuilt = true
        let card = segmentedCardBackground!
        card.clipsToBounds = false
        
        let ws = UIColor.whiteSmoke
        let onyx = UIColor(named: "Onyx") ?? .black
        let limeMoss = UIColor(named: "Lime Moss") ?? .systemGreen
        let beige = UIColor(named: "Beige") ?? .systemGray5
        
        // --- Left Pill (Revenue Pill) ---
        leftPillButton = UIButton(type: .system)
        leftPillButton.setTitle("Revenue", for: .normal)
        leftPillButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        leftPillButton.backgroundColor = limeMoss
        leftPillButton.setTitleColor(ws, for: .normal)
        leftPillButton.layer.cornerRadius = 18
        leftPillButton.clipsToBounds = true
        leftPillButton.translatesAutoresizingMaskIntoConstraints = false
        leftPillButton.addTarget(self, action: #selector(switchTabTapped), for: .touchUpInside)
        card.addSubview(leftPillButton)
        
        // --- Right Pill (Investment Pill) ---
        rightPillButton = UIButton(type: .system)
        rightPillButton.setTitle("Investment", for: .normal)
        rightPillButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        rightPillButton.backgroundColor = beige
        rightPillButton.setTitleColor(onyx, for: .normal)
        rightPillButton.layer.cornerRadius = 18
        rightPillButton.clipsToBounds = true
        rightPillButton.translatesAutoresizingMaskIntoConstraints = false
        rightPillButton.addTarget(self, action: #selector(switchTabTapped), for: .touchUpInside)
        card.addSubview(rightPillButton)
        
        // --- Left Text Group (Revenue) ---
        leftTitleLabel = UILabel()
        leftTitleLabel.text = "Revenue"
        leftTitleLabel.textColor = ws
        leftTitleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        leftTitleLabel.isUserInteractionEnabled = true
        leftTitleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleChevronTapped)))
        leftTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(leftTitleLabel)
        
        // Chevrons removed — tapping the card (outside chart) opens the detail view
        leftChevron = UIButton(type: .system)
        leftChevron.isHidden = true
        leftChevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(leftChevron)
        
        leftSubtitleLabel = UILabel()
        leftSubtitleLabel.text = "Total"
        leftSubtitleLabel.textColor = ws.withAlphaComponent(0.75)
        leftSubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        leftSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(leftSubtitleLabel)
        
        leftAmountLabel = UILabel()
        leftAmountLabel.textColor = ws
        leftAmountLabel.font = .systemFont(ofSize: 30, weight: .bold)
        leftAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(leftAmountLabel)
        
        // --- Right Text Group (Investment) ---
        rightTitleLabel = UILabel()
        rightTitleLabel.text = "Investment"
        rightTitleLabel.textColor = onyx
        rightTitleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        rightTitleLabel.isUserInteractionEnabled = true
        rightTitleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleChevronTapped)))
        rightTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rightTitleLabel)
        
        rightChevron = UIButton(type: .system)
        rightChevron.isHidden = true
        rightChevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rightChevron)
        
        rightSubtitleLabel = UILabel()
        rightSubtitleLabel.text = "Total"
        rightSubtitleLabel.textColor = onyx.withAlphaComponent(0.6)
        rightSubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        rightSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rightSubtitleLabel)
        
        rightAmountLabel = UILabel()
        rightAmountLabel.textColor = onyx
        rightAmountLabel.font = .systemFont(ofSize: 30, weight: .bold)
        rightAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rightAmountLabel)
        
        // --- Chart ---
        chartView = BarChartView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.backgroundColor = .clear
        chartView.delegate = self
        configureChartAppearance(chartView)
        card.addSubview(chartView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Left Pill
            leftPillButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            leftPillButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            leftPillButton.widthAnchor.constraint(equalToConstant: 134),
            leftPillButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Right Pill
            rightPillButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            rightPillButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            rightPillButton.widthAnchor.constraint(equalToConstant: 134),
            rightPillButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Left Text Group
            leftTitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            leftTitleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            leftTitleLabel.heightAnchor.constraint(equalToConstant: 24),
            
            leftChevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -190),
            leftChevron.leadingAnchor.constraint(greaterThanOrEqualTo: leftTitleLabel.trailingAnchor, constant: 8),
            leftChevron.centerYAnchor.constraint(equalTo: leftTitleLabel.centerYAnchor, constant: 1),
            
            leftSubtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            leftSubtitleLabel.topAnchor.constraint(equalTo: leftTitleLabel.bottomAnchor, constant: 3),
            
            leftAmountLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            leftAmountLabel.topAnchor.constraint(equalTo: leftSubtitleLabel.bottomAnchor, constant: 2),
            
            // Right Text Group
            rightTitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            rightTitleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            rightTitleLabel.heightAnchor.constraint(equalToConstant: 24),
            
            rightChevron.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 190),
            rightChevron.trailingAnchor.constraint(lessThanOrEqualTo: rightTitleLabel.leadingAnchor, constant: -8),
            rightChevron.centerYAnchor.constraint(equalTo: rightTitleLabel.centerYAnchor, constant: 1),
            
            rightSubtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            rightSubtitleLabel.topAnchor.constraint(equalTo: rightTitleLabel.bottomAnchor, constant: 3),
            
            rightAmountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            rightAmountLabel.topAnchor.constraint(equalTo: rightSubtitleLabel.bottomAnchor, constant: 2),
            
            // Chart
            chartView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            chartView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            chartView.topAnchor.constraint(equalTo: leftAmountLabel.bottomAnchor, constant: 4), // Tighten chart gap to offset the whole text block drop
            chartView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
        ])
        
        // Add a tap overlay on the title+amount area (above the chart) for navigation
        let tapOverlay = UIView()
        tapOverlay.translatesAutoresizingMaskIntoConstraints = false
        tapOverlay.backgroundColor = .clear
        tapOverlay.isUserInteractionEnabled = true
        tapOverlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleChevronTapped)))
        card.addSubview(tapOverlay)
        
        NSLayoutConstraint.activate([
            tapOverlay.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tapOverlay.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tapOverlay.topAnchor.constraint(equalTo: card.topAnchor),
            tapOverlay.bottomAnchor.constraint(equalTo: chartView.topAnchor),
        ])
        
        // Bring pill buttons above the overlay so they stay tappable
        card.bringSubviewToFront(leftPillButton)
        card.bringSubviewToFront(rightPillButton)
        
        applyState(animated: false)
    }
    
    // MARK: - Tap Actions
    @objc private func switchTabTapped() {
        if activeTab == .revenue {
            activeTab = .investment
        } else {
            activeTab = .revenue
        }
        applyState(animated: true)
        refreshCharts()
    }
    
    @objc private func titleChevronTapped() {
        if activeTab == .revenue {
            revenueTapped?()
            delegate?.topTileCellDidTapRevenue(self)
        } else {
            investmentTapped?()
            delegate?.topTileCellDidTapInvestment(self)
        }
    }
    
    // MARK: - Apply State
    private func applyState(animated: Bool) {
        let limeMoss = UIColor(named: "Lime Moss") ?? .systemGreen
        let beige = UIColor(named: "Beige") ?? .systemGray5
        let onyx = UIColor(named: "Onyx") ?? .black
        let ws = UIColor.whiteSmoke
        
        let apply = {
            if self.activeTab == .revenue {
                // Card Shape
                self.segmentedCardBackground.fillColor = limeMoss
                self.segmentedCardBackground.cutoutOnRight = true
                
                // Show left text, hide right text
                self.leftTitleLabel.alpha = 1
                self.leftChevron.alpha = 1
                self.leftSubtitleLabel.alpha = 1
                self.leftAmountLabel.alpha = 1
                self.leftAmountLabel.text = self.storedRevenueAmount
                
                self.rightTitleLabel.alpha = 0
                self.rightChevron.alpha = 0
                self.rightSubtitleLabel.alpha = 0
                self.rightAmountLabel.alpha = 0
                
                // Show right pill, hide left pill
                self.leftPillButton.alpha = 0
                self.rightPillButton.alpha = 1
                
                // Chart Setup
                self.chartView.xAxis.labelTextColor = ws
                self.chartView.leftAxis.labelTextColor = ws.withAlphaComponent(0.6)
                self.chartView.leftAxis.gridColor = ws.withAlphaComponent(0.2)
                
            } else {
                // Card Shape
                self.segmentedCardBackground.fillColor = beige
                self.segmentedCardBackground.cutoutOnRight = false
                
                // Hide left text, show right text
                self.leftTitleLabel.alpha = 0
                self.leftChevron.alpha = 0
                self.leftSubtitleLabel.alpha = 0
                self.leftAmountLabel.alpha = 0
                
                self.rightTitleLabel.alpha = 1
                self.rightChevron.alpha = 1
                self.rightSubtitleLabel.alpha = 1
                self.rightAmountLabel.alpha = 1
                self.rightAmountLabel.text = self.storedInvestmentAmount
                
                // Show left pill, hide right pill
                self.leftPillButton.alpha = 1
                self.rightPillButton.alpha = 0
                
                // Chart Setup
                self.chartView.xAxis.labelTextColor = onyx
                self.chartView.leftAxis.labelTextColor = onyx.withAlphaComponent(0.5)
                self.chartView.leftAxis.gridColor = onyx.withAlphaComponent(0.15)
            }
            
            self.segmentedCardBackground.setNeedsDisplay()
        }
        
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }
    
    // MARK: - Public API
    func configure(revenueAmount: String, investmentAmount: String, lowStockCountText: String, expiryCountText: String, youWillGetAmount: Double = 0, youWillPayAmount: Double = 0) {
        self.storedRevenueAmount = revenueAmount
        self.storedInvestmentAmount = investmentAmount
        applyState(animated: false)
        
        restockCountLabel.text = lowStockCountText
        expiryCountLabel?.text = expiryCountText
        expiryCountLabel?.textColor = .label
        
        if youWillGetAmount > 0 {
            youWillGetLabel?.text = String(format: "₹%.0f", youWillGetAmount)
            youWillGetLabel?.textColor = UIColor(named: "Lime Moss")!
        } else {
            youWillGetLabel?.text = "₹0"
            youWillGetLabel?.textColor = .secondaryLabel
        }
        
        if youWillPayAmount > 0 {
            youWillPayLabel?.text = String(format: "₹%.0f", youWillPayAmount)
            youWillPayLabel?.textColor = .systemRed
        } else {
            youWillPayLabel?.text = "₹0"
            youWillPayLabel?.textColor = .secondaryLabel
        }
    }
    
    // MARK: - Chart
    func configureChartAppearance(_ chart: BarChartView) {
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        
        chart.dragEnabled = false
        chart.pinchZoomEnabled = false
        chart.scaleXEnabled = false
        chart.scaleYEnabled = false
        
        // Left Y axis
        chart.leftAxis.enabled = true
        chart.leftAxis.drawLabelsEnabled = true
        chart.leftAxis.drawAxisLineEnabled = false
        chart.leftAxis.drawGridLinesEnabled = true
        chart.leftAxis.gridColor = UIColor.whiteSmoke.withAlphaComponent(0.2)
        chart.leftAxis.gridLineDashLengths = [4, 3]
        chart.leftAxis.labelFont = .systemFont(ofSize: 9, weight: .medium)
        chart.leftAxis.labelTextColor = .whiteSmoke.withAlphaComponent(0.6)
        chart.leftAxis.labelCount = 4
        chart.leftAxis.axisMinimum = 0
        chart.leftAxis.granularity = 1
        
        chart.rightAxis.enabled = false
        
        // X axis
        chart.xAxis.labelPosition = .bottom
        chart.xAxis.drawGridLinesEnabled = false
        chart.xAxis.drawAxisLineEnabled = false
        chart.xAxis.labelFont = .systemFont(ofSize: 10, weight: .semibold)
        chart.xAxis.labelTextColor = .whiteSmoke
        chart.xAxis.granularity = 1
        chart.xAxis.labelCount = 7
        chart.xAxis.forceLabelsEnabled = true
        
        chart.setExtraOffsets(left: 8, top: 4, right: 8, bottom: 4)
        chart.minOffset = 0
    }

    func configureCharts(with weeklyData: [String: WeekData]) {
        self.weeklyData = weeklyData
        refreshCharts()
    }

    func refreshCharts() {
        guard chartView != nil else { return }
        
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayIndex = weekday - 1
        var rotatedDays: [String] = []
        
        for i in stride(from: 6, through: 0, by: -1) {
            let index = (todayIndex - i + 7) % 7
            rotatedDays.append(orderedDays[index])
        }
        
        var displayLabels = rotatedDays
        displayLabels[displayLabels.count - 1] = "Tod"
        
        var entries: [BarChartDataEntry] = []
        var colors: [UIColor] = []
        let onyx = UIColor(named: "Onyx") ?? .black
        
        for (index, day) in rotatedDays.enumerated() {
            let value = activeTab == .revenue
                ? (weeklyData[day]?.revenue ?? 0)
                : (weeklyData[day]?.investment ?? 0)
            let isToday = index == rotatedDays.count - 1
            
            entries.append(BarChartDataEntry(x: Double(index), y: max(value, 0.2)))
            
            if activeTab == .revenue {
                colors.append(isToday ? .whiteSmoke : .whiteSmoke.withAlphaComponent(0.35))
            } else {
                colors.append(isToday ? onyx : onyx.withAlphaComponent(0.35))
            }
        }
        
        let dataSet = BarChartDataSet(entries: entries)
        dataSet.colors = colors
        dataSet.drawValuesEnabled = false
        
        let data = BarChartData(dataSet: dataSet)
        data.barWidth = 0.5
        
        chartView.data = data
        chartView.fitBars = true
        
        let formatter = IndexAxisValueFormatter(values: displayLabels)
        chartView.xAxis.valueFormatter = formatter
        chartView.xAxis.labelCount = 7
        
        chartView.notifyDataSetChanged()
        chartView.animate(yAxisDuration: 0.3, easingOption: .easeOutCubic)
    }
}

extension DashboardTopTileTableViewCell: ChartViewDelegate {
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayIndex = weekday - 1
        var rotatedDays: [String] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let index = (todayIndex - i + 7) % 7
            rotatedDays.append(orderedDays[index])
        }
        
        let dayIndex = Int(entry.x)
        guard dayIndex >= 0 && dayIndex < rotatedDays.count else { return }
        let selectedDay = rotatedDays[dayIndex]
        let isToday = dayIndex == rotatedDays.count - 1
        
        // Match the text in the chart exactly or use full name
        let dayNamesMap = ["Sun": "Sunday", "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday"]
        let dayLabel = isToday ? "Today" : (dayNamesMap[selectedDay] ?? selectedDay)
        
        let value = activeTab == .revenue 
            ? (weeklyData[selectedDay]?.revenue ?? 0)
            : (weeklyData[selectedDay]?.investment ?? 0)
            
        let formattedValue = String(format: "₹%.0f", value)
        
        if activeTab == .revenue {
            leftAmountLabel.text = formattedValue
            leftSubtitleLabel.text = dayLabel
        } else {
            rightAmountLabel.text = formattedValue
            rightSubtitleLabel.text = dayLabel
        }
    }
    
    func chartValueNothingSelected(_ chartView: ChartViewBase) {
        if activeTab == .revenue {
            leftAmountLabel.text = storedRevenueAmount
            leftSubtitleLabel.text = "Total"
        } else {
            rightAmountLabel.text = storedInvestmentAmount
            rightSubtitleLabel.text = "Total"
        }
    }
}
