import UIKit
import DGCharts

class ProfitAndLossTopTileTableViewCell: UITableViewCell {

    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var changeLabel: UILabel!
    @IBOutlet weak var lineChartView: BarChartView!
    private lazy var currencyMarker = makeMarker()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupCharts()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
            super.setSelected(selected, animated: animated)
        }
        
    func setupCharts() {
        let chart = lineChartView!
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

        chart.xAxis.labelPosition = .bottom
        chart.xAxis.drawGridLinesEnabled = false
        chart.xAxis.drawAxisLineEnabled = false
        chart.xAxis.labelTextColor = .black
        chart.xAxis.granularity = 1
        chart.xAxis.granularityEnabled = true
    }
        
    func configure(
        totalAmount: Double,
        growthText: String,
        lineChartPoints: [ChartDataProvider.ChartPoint]
    ) {
        amountLabel.text = "₹\(Int(totalAmount))"
        changeLabel.text = growthText

        guard !lineChartPoints.isEmpty else {
            lineChartView.data = nil
            lineChartView.noDataText = "No Data"
            return
        }

        let entries = lineChartPoints.enumerated().map {
            BarChartDataEntry(x: Double($0.offset), y: $0.element.value)
        }
        let xLabels = lineChartPoints.map { $0.label }
        let count = xLabels.count

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.colors = [UIColor(red: 0.76, green: 0.78, blue: 0.55, alpha: 1.0)]
        dataSet.drawValuesEnabled = false

        let barData = BarChartData(dataSet: dataSet)
        barData.barWidth = 0.5
        lineChartView.data = barData
        lineChartView.highlightValue(nil)

        // X-Axis: force show ALL labels
        let xAxis = lineChartView.xAxis
        xAxis.valueFormatter = IndexAxisValueFormatter(values: xLabels)
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.labelCount = count
        xAxis.forceLabelsEnabled = false
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
        marker.setLabel("₹0")
        return marker
    }

    private func currencyText(for value: Double) -> String {
        "₹\(Int(value.rounded()))"
    }
}
