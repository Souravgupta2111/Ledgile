import UIKit
import DGCharts

class StockAnalysisTopTileTableViewCell: UITableViewCell {
    @IBOutlet weak var itemsSoldCount: UILabel!
    
    @IBOutlet weak var itemsSoldChartView: BarChartView!

    @IBOutlet weak var firstFastMovingItem: UILabel!
    @IBOutlet weak var secondFastMovingItem: UILabel!
    @IBOutlet weak var thirdFastMovingItem: UILabel!
    
    @IBOutlet weak var firstSlowMovingItem: UILabel!
    @IBOutlet weak var secondSlowMovingItem: UILabel!
    @IBOutlet weak var thirdSlowMovingItem: UILabel!
    private lazy var quantityMarker = makeMarker()
    
    override func awakeFromNib() {
            super.awakeFromNib()
        }

    func setupBarChart() {
        let chart = itemsSoldChartView!

        chart.rightAxis.enabled = false
        chart.leftAxis.enabled = true
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        chart.marker = quantityMarker
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

        // X Axis
        let xAxis = chart.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = false
        xAxis.labelTextColor = .blackWhite
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.labelRotationAngle = 0

        // Left Axis
        let leftAxis = chart.leftAxis
        leftAxis.enabled = true
        leftAxis.axisMinimum = 0
        leftAxis.labelTextColor = .blackWhite
        leftAxis.drawGridLinesEnabled = true
        leftAxis.drawAxisLineEnabled = false
        leftAxis.gridColor = .graphLine
        leftAxis.gridLineDashLengths = [4, 4]
    }
    
    func configure(
            chartPoints: [ChartDataProvider.ChartPoint],
            items: [ChartDataProvider.ProfitItem]
        ) {
            let sortedItems = items.sorted { lhs, rhs in
                if lhs.quantity != rhs.quantity {
                    return lhs.quantity > rhs.quantity
                }

                let lhsRevenue = lhs.sellingPrice * Double(lhs.quantity)
                let rhsRevenue = rhs.sellingPrice * Double(rhs.quantity)
                if lhsRevenue != rhsRevenue {
                    return lhsRevenue > rhsRevenue
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            setupBarChart()
            setupItemsSoldBar(chartPoints)
            
            setupFastMoving(sortedItems)
            setupSlowMoving(sortedItems)

            let total = sortedItems.reduce(0) { $0 + $1.quantity }
            itemsSoldCount.text = "\(total)"
    }

        func setupItemsSoldBar(_ points: [ChartDataProvider.ChartPoint]) {
            let entries = points.enumerated().map {
                BarChartDataEntry(x: Double($0.offset), y: $0.element.value)
            }
            let xLabels = points.map { $0.label }
            let count = xLabels.count

            let dataSet = BarChartDataSet(entries: entries, label: "")
            dataSet.colors = [UIColor(red: 0.76, green: 0.78, blue: 0.55, alpha: 1.0)]
            dataSet.drawValuesEnabled = false

            let data = BarChartData(dataSet: dataSet)
            data.barWidth = 0.5
            itemsSoldChartView.data = data
            itemsSoldChartView.highlightValue(nil)
            
            // X-Axis: force show ALL labels
            let xAxis = itemsSoldChartView.xAxis
            xAxis.valueFormatter = IndexAxisValueFormatter(values: xLabels)
            xAxis.granularity = 1
            xAxis.granularityEnabled = true
            xAxis.labelCount = count
            xAxis.forceLabelsEnabled = false
            xAxis.avoidFirstLastClippingEnabled = true
            xAxis.labelFont = .systemFont(ofSize: 10)
            xAxis.axisMinimum = -0.5
            xAxis.axisMaximum = Double(count) - 0.5
            xAxis.centerAxisLabelsEnabled = false

            itemsSoldChartView.fitBars = true
            itemsSoldChartView.setVisibleXRangeMaximum(Double(count))
            itemsSoldChartView.setVisibleXRangeMinimum(Double(count))
            
            itemsSoldChartView.leftAxis.granularity = 1
            itemsSoldChartView.leftAxis.granularityEnabled = true
            itemsSoldChartView.leftAxis.valueFormatter = DefaultAxisValueFormatter(decimals: 0)

            itemsSoldChartView.animate(yAxisDuration: 0.6)
        }

    private func makeMarker() -> ChartTooltipMarker {
        let marker = ChartTooltipMarker(
            color: UIColor.systemBackground.withAlphaComponent(0.95),
            font: .systemFont(ofSize: 12, weight: .semibold),
            textColor: .label,
            insets: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        )
        marker.minimumSize = CGSize(width: 48, height: 32)
        marker.textProvider = { [weak self] entry in
            self?.quantityText(for: entry.y) ?? "0"
        }
        marker.setLabel("0")
        return marker
    }

    private func quantityText(for value: Double) -> String {
        "\(Int(value.rounded()))"
    }


    func setupFastMoving(_ items: [ChartDataProvider.ProfitItem]) {

        let top = Array(items.prefix(3))

        let maxLabelLength = 24

        let formatted = top.map {
            let name = $0.name.count > maxLabelLength
                ? String($0.name.prefix(maxLabelLength)) + "…"
                : $0.name
            return "\(name)"
        }

        firstFastMovingItem.text = formatted.indices.contains(0) ? formatted[0] : "-"
        secondFastMovingItem.text = formatted.indices.contains(1) ? formatted[1] : "-"
        thirdFastMovingItem.text = formatted.indices.contains(2) ? formatted[2] : "-"
    }


    func setupSlowMoving(_ items: [ChartDataProvider.ProfitItem]) {

        let bottom = Array(items.suffix(3)).reversed()

        let maxLabelLength = 24

        let formatted = bottom.map {
            let name = $0.name.count > maxLabelLength
                ? String($0.name.prefix(maxLabelLength)) + "…"
                : $0.name
            return "\(name)"
        }

        firstSlowMovingItem.text = formatted.indices.contains(0) ? formatted[0] : "-"
        secondSlowMovingItem.text = formatted.indices.contains(1) ? formatted[1] : "-"
        thirdSlowMovingItem.text = formatted.indices.contains(2) ? formatted[2] : "-"
    }
    
}
