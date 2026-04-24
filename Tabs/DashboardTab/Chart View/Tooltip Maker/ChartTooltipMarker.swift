
import UIKit
import DGCharts

class ChartTooltipMarker: MarkerView {
    let label: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()
    var color: UIColor
    var arrowSize = CGSize(width: 15, height: 10)
    var font: UIFont
    var textColor: UIColor
    var insets: UIEdgeInsets
    var minimumSize = CGSize()
    var textProvider: ((ChartDataEntry) -> String)?
    private var drawsAbovePoint = true

    init(color: UIColor, font: UIFont, textColor: UIColor, insets: UIEdgeInsets) {
        self.color = color
        self.font = font
        self.textColor = textColor
        self.insets = insets
        super.init(frame: .zero)
        label.font = font
        label.textColor = textColor
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func setLabel(_ text: String) {
        label.text = text
        let labelSize = text.size(withAttributes: [NSAttributedString.Key.font: font])
        let width = max(minimumSize.width, labelSize.width + insets.left + insets.right)
        let bubbleHeight = max(minimumSize.height, labelSize.height + insets.top + insets.bottom)
        self.frame.size = CGSize(width: width, height: bubbleHeight + arrowSize.height)
        layoutLabel(labelSize: labelSize)
        setNeedsDisplay()
    }

    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        let text = textProvider?(entry) ?? "\(entry.y)"
        setLabel(text)
        super.refreshContent(entry: entry, highlight: highlight)
    }
    
    override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
        let width = self.bounds.size.width
        let height = self.bounds.size.height
        let arrowGap: CGFloat = 6

        var shouldDrawAbove = true

        if let chart = chartView {
            let requiredAbove = height + arrowGap
            let requiredBelow = height + arrowGap
            let hasRoomAbove = point.y >= requiredAbove
            let hasRoomBelow = (chart.bounds.height - point.y) >= requiredBelow

            if !hasRoomAbove && hasRoomBelow {
                shouldDrawAbove = false
            } else if !hasRoomAbove && !hasRoomBelow {
                shouldDrawAbove = point.y >= (chart.bounds.height - point.y)
            }
        }

        if drawsAbovePoint != shouldDrawAbove {
            drawsAbovePoint = shouldDrawAbove
            if let text = label.text {
                let size = text.size(withAttributes: [.font: font])
                layoutLabel(labelSize: size)
            }
        }

        var offset = CGPoint(
            x: -width / 2,
            y: drawsAbovePoint ? -(height + arrowGap) : arrowGap
        )

        if let chart = chartView {
            let minX = point.x + offset.x
            let maxX = minX + width

            if minX < 0 {
                offset.x -= minX
            } else if maxX > chart.bounds.width {
                offset.x -= (maxX - chart.bounds.width)
            }

            let minY = point.y + offset.y
            let maxY = minY + height

            if minY < 0 {
                offset.y -= minY
            } else if maxY > chart.bounds.height {
                offset.y -= (maxY - chart.bounds.height)
            }
        }

        return offset
    }

    override func draw(context: CGContext, point: CGPoint) {
        let offset = self.offsetForDrawing(atPoint: point)
        let origin = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        let rect = CGRect(origin: origin, size: self.bounds.size)
        let bubbleRect = drawsAbovePoint
            ? CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height - arrowSize.height
            )
            : CGRect(
                x: rect.origin.x,
                y: rect.origin.y + arrowSize.height,
                width: rect.width,
                height: rect.height - arrowSize.height
            )

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.2).cgColor)
        let path = UIBezierPath()
        let radius: CGFloat = 8
        let arrowWidthHalf = arrowSize.width / 2
        let arrowX = min(
            max(point.x, bubbleRect.minX + radius + arrowWidthHalf),
            bubbleRect.maxX - radius - arrowWidthHalf
        )

        if drawsAbovePoint {
            path.move(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.minY))
            path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.minY + radius), radius: radius, startAngle: -.pi/2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - radius))
            path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.maxY - radius), radius: radius, startAngle: 0, endAngle: .pi/2, clockwise: true)
            path.addLine(to: CGPoint(x: arrowX + arrowWidthHalf, y: bubbleRect.maxY))
            path.addLine(to: CGPoint(x: arrowX, y: bubbleRect.maxY + arrowSize.height))
            path.addLine(to: CGPoint(x: arrowX - arrowWidthHalf, y: bubbleRect.maxY))
            path.addLine(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.maxY))
            path.addArc(withCenter: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.maxY - radius), radius: radius, startAngle: .pi/2, endAngle: .pi, clockwise: true)
            path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + radius))
            path.addArc(withCenter: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY + radius), radius: radius, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        } else {
            path.move(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: arrowX - arrowWidthHalf, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: arrowX, y: bubbleRect.minY - arrowSize.height))
            path.addLine(to: CGPoint(x: arrowX + arrowWidthHalf, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.minY))
            path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.minY + radius), radius: radius, startAngle: -.pi/2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - radius))
            path.addArc(withCenter: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.maxY - radius), radius: radius, startAngle: 0, endAngle: .pi/2, clockwise: true)
            path.addLine(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.maxY))
            path.addArc(withCenter: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.maxY - radius), radius: radius, startAngle: .pi/2, endAngle: .pi, clockwise: true)
            path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + radius))
            path.addArc(withCenter: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY + radius), radius: radius, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        }
        path.close()
        context.setFillColor(color.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()
        // Write Text Manually
        let text = label.text ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: NSMutableParagraphStyle(),
            .foregroundColor: textColor
        ]
        // Calculate text geometry
        let textRect = CGRect(
            x: rect.origin.x + label.frame.origin.x,
            y: rect.origin.y + label.frame.origin.y,
            width: label.frame.width,
            height: label.frame.height
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let centeredAttrs = attributes.merging([.paragraphStyle: paragraphStyle]) { (_, new) in new }
        (text as NSString).draw(in: textRect, withAttributes: centeredAttrs)
    }

    private func layoutLabel(labelSize: CGSize) {
        let bubbleWidth = bounds.width
        let bubbleHeight = max(bounds.height - arrowSize.height, 0)
        let bubbleOriginY = drawsAbovePoint ? CGFloat.zero : arrowSize.height

        label.frame = CGRect(
            x: insets.left + (bubbleWidth - insets.left - insets.right - labelSize.width) / 2,
            y: bubbleOriginY + insets.top + (bubbleHeight - insets.top - insets.bottom - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }
}
