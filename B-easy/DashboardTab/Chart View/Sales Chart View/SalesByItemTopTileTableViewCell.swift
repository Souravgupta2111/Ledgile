import UIKit
import DGCharts
class SalesByItemTopTileTableViewCell: UITableViewCell {

    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var changeLabel: UILabel!
    @IBOutlet weak var lineChartView: BarChartView!
    @IBOutlet weak var topItemLabel: UILabel!
    @IBOutlet weak var barChartView: BarChartView!
    @IBOutlet weak var itemsSoldCount: UILabel!
    private lazy var currencyMarker = makeMarker()
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupCharts()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
            super.setSelected(selected, animated: animated)
        }
        
    func setupCharts() {
        // --- Main chart ---
        configureBarChartDefaults(lineChartView)

        // --- Bottom bar chart ---
        configureBarChartDefaults(barChartView)
        barChartView.setViewPortOffsets(left: 4, top: 4, right: 4, bottom: 24)
    }

    private func configureBarChartDefaults(_ chart: BarChartView) {
        chart.rightAxis.enabled = false
        chart.leftAxis.enabled = true
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        chart.marker = currencyMarker
        chart.highlightPerTapEnabled = true
        chart.highlightPerDragEnabled = false
        chart.drawMarkers = true
        chart.drawValueAboveBarEnabled = false
        chart.dragEnabled = false
        chart.pinchZoomEnabled = false
        chart.scaleXEnabled = false
        chart.scaleYEnabled = false
        chart.doubleTapToZoomEnabled = false
        chart.extraTopOffset = 30
        chart.leftAxis.spaceTop = 0.15

        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawGridLinesEnabled = false
        xAxis.drawAxisLineEnabled = false
        xAxis.labelTextColor = .black
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
    }
        
    func configure(
        totalAmount: Double,
        growthText: String,
        itemsSold: Int,
        topItem: String,
        lineChartPoints: [ChartDataProvider.ChartPoint],
        barChartValues: [Double],
        barChartLabels: [String],
        period: ChartDataProvider.Period
    ) {
        amountLabel.text = "₹\(Int(totalAmount))"
        changeLabel.text = growthText
        itemsSoldCount.text = "\(itemsSold)"
        topItemLabel.text = topItem

        // --- Main chart ---
        configureMainChart(lineChartPoints)

        // --- Bottom bar chart (item-level) ---
        configureBottomChart(barChartValues, barChartLabels)
    }

    private func configureMainChart(_ points: [ChartDataProvider.ChartPoint]) {
        guard !points.isEmpty else {
            lineChartView.data = nil
            lineChartView.noDataText = "No Data"
            return
        }

        let entries = points.enumerated().map {
            BarChartDataEntry(x: Double($0.offset), y: $0.element.value)
        }
        let xLabels = points.map { $0.label }
        let count = xLabels.count

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.colors = [UIColor(red: 0.76, green: 0.78, blue: 0.55, alpha: 1.0)]
        dataSet.drawValuesEnabled = false

        let barData = BarChartData(dataSet: dataSet)
        barData.barWidth = 0.5

        lineChartView.data = barData
        updateMarker(for: lineChartView)

        // X-Axis: force show ALL labels
        let xAxis = lineChartView.xAxis
        xAxis.valueFormatter = IndexAxisValueFormatter(values: xLabels)
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.labelCount = count
        xAxis.forceLabelsEnabled = false   // let granularity control label count
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.labelRotationAngle = 0
        xAxis.labelFont = .systemFont(ofSize: 10)
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = false
        xAxis.labelTextColor = .blackWhite
        xAxis.axisMinimum = -0.5
        xAxis.axisMaximum = Double(count) - 0.5
        xAxis.centerAxisLabelsEnabled = false

        // Y-Axis
        lineChartView.leftAxis.axisMinimum = 0
        lineChartView.leftAxis.labelTextColor = .blackWhite
        lineChartView.leftAxis.drawGridLinesEnabled = true
        lineChartView.leftAxis.drawAxisLineEnabled = false
        lineChartView.leftAxis.gridColor = .graphLine
        lineChartView.leftAxis.gridLineDashLengths = [4, 4]

        lineChartView.fitBars = true
        lineChartView.setVisibleXRangeMaximum(Double(count))
        lineChartView.setVisibleXRangeMinimum(Double(count))
        lineChartView.animate(yAxisDuration: 0.6)
        lineChartView.notifyDataSetChanged()
    }

    private func configureBottomChart(_ values: [Double], _ labels: [String]) {
        let count = labels.count
        let filledValues: [Double] = labels.enumerated().map { i in
            i.offset < values.count ? values[i.offset] : 0
        }

        let barEntries = filledValues.enumerated().map {
            BarChartDataEntry(x: Double($0.offset), y: $0.element)
        }
        let barSet = BarChartDataSet(entries: barEntries, label: "")
        barSet.colors = [UIColor(red: 0.76, green: 0.78, blue: 0.55, alpha: 1.0)]
        barSet.drawValuesEnabled = false

        let barData = BarChartData(dataSet: barSet)
        barData.barWidth = 0.3
        barChartView.data = barData
        updateMarker(for: barChartView)

        let shortLabels = labels.map { String($0.prefix(1)) }

        // X-Axis: force show ALL labels
        let xAxis = barChartView.xAxis
        xAxis.valueFormatter = IndexAxisValueFormatter(values: shortLabels)
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.centerAxisLabelsEnabled = false
        xAxis.labelCount = count
        xAxis.forceLabelsEnabled = false
        xAxis.avoidFirstLastClippingEnabled = true
        xAxis.labelRotationAngle = 0
        xAxis.labelFont = .systemFont(ofSize: 8)
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = false
        xAxis.labelTextColor = .blackWhite
        xAxis.axisMinimum = -0.5
        xAxis.axisMaximum = Double(count) - 0.5

        barChartView.leftAxis.drawAxisLineEnabled = false
        barChartView.leftAxis.axisMinimum = 0
        barChartView.leftAxis.drawGridLinesEnabled = false
        barChartView.leftAxis.drawLabelsEnabled = false

        barChartView.fitBars = true
        barChartView.setVisibleXRangeMaximum(Double(count))
        barChartView.setVisibleXRangeMinimum(Double(count))
        barChartView.moveViewToX(0)
        barChartView.notifyDataSetChanged()
    }

    private func makeMarker() -> ChartTooltipMarker {
        let marker = ChartTooltipMarker(
            color: UIColor.systemBackground.withAlphaComponent(0.95),
            font: .systemFont(ofSize: 12, weight: .semibold),
            textColor: .label,
            insets: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        )
        marker.minimumSize = CGSize(width: 56, height: 32)
        marker.textProvider = { [weak self] entry in
            self?.currencyText(for: entry.y) ?? "₹0"
        }
        return marker
    }

    private func updateMarker(for chartView: ChartViewBase) {
        guard let marker = chartView.marker as? ChartTooltipMarker else { return }
        chartView.highlightValue(nil)

        let firstValue = chartView.data?.dataSets.first?.entryForIndex(0)?.y ?? 0
        marker.setLabel(currencyText(for: firstValue))
    }

    private func currencyText(for value: Double) -> String {
        "₹\(Int(value.rounded()))"
    }
}
