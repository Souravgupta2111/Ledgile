import UIKit

@IBDesignable
class SegmentedCardBackgroundView: UIView {
    
    var cutoutWidth: CGFloat = 142 { didSet { setNeedsDisplay() } }
    var cutoutHeight: CGFloat = 46 { didSet { setNeedsDisplay() } }
    var cornerRadius: CGFloat = 16 { didSet { setNeedsDisplay() } }
    
    var cutoutOnRight: Bool = true { didSet { setNeedsDisplay() } }
    
    @IBInspectable var fillColor: UIColor = .darkGray {
        didSet { setNeedsDisplay() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
    }
    
    override func draw(_ rect: CGRect) {
        if cutoutOnRight {
            drawRightCutout(in: rect)
        } else {
            drawLeftCutout(in: rect)
        }
    }
    
    private func drawRightCutout(in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        let r = cornerRadius
        let cw = cutoutWidth
        let ch = cutoutHeight
        let path = UIBezierPath()
        let slantOffset: CGFloat = 34
        
        path.move(to: CGPoint(x: 0, y: r))
        // Top-left corner
        path.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        
        // Top edge to the start of the slant
        path.addLine(to: CGPoint(x: w - cw - slantOffset, y: 0))
        
        // Smooth slanted S-curve down to the lower lip
        path.addCurve(
            to: CGPoint(x: w - cw, y: ch),
            controlPoint1: CGPoint(x: w - cw - slantOffset + 12, y: 0),
            controlPoint2: CGPoint(x: w - cw - 12, y: ch)
        )
        
        // Lower lip top edge
        path.addLine(to: CGPoint(x: w - r, y: ch))
        // Top-right outer corner
        path.addArc(withCenter: CGPoint(x: w - r, y: ch + r), radius: r, startAngle: -.pi/2, endAngle: 0, clockwise: true)
        
        // Right edge
        path.addLine(to: CGPoint(x: w, y: h - r))
        // Bottom-right corner
        path.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)
        
        // Bottom edge
        path.addLine(to: CGPoint(x: r, y: h))
        // Bottom-left corner
        path.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)
        path.close()
        
        fillColor.setFill()
        path.fill()
    }
    
    private func drawLeftCutout(in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        let r = cornerRadius
        let cw = cutoutWidth
        let ch = cutoutHeight
        let path = UIBezierPath()
        let slantOffset: CGFloat = 34
        
        // Start at the lower lip's top-left corner
        path.move(to: CGPoint(x: 0, y: ch + r))
        path.addArc(withCenter: CGPoint(x: r, y: ch + r), radius: r, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
        
        // Lower lip top edge
        path.addLine(to: CGPoint(x: cw, y: ch))
        
        // Smooth slanted S-curve UP to the top lip
        path.addCurve(
            to: CGPoint(x: cw + slantOffset, y: 0),
            controlPoint1: CGPoint(x: cw + 12, y: ch),
            controlPoint2: CGPoint(x: cw + slantOffset - 12, y: 0)
        )
        
        // Top edge
        path.addLine(to: CGPoint(x: w - r, y: 0))
        // Top-right corner
        path.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r, startAngle: -.pi/2, endAngle: 0, clockwise: true)
        
        // Right edge
        path.addLine(to: CGPoint(x: w, y: h - r))
        // Bottom-right corner
        path.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)
        
        // Bottom edge
        path.addLine(to: CGPoint(x: r, y: h))
        // Bottom-left corner
        path.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)
        path.close()
        
        fillColor.setFill()
        path.fill()
    }
}
