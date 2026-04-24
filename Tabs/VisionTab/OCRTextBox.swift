//  Represents a single text region detected by OCR with spatial data.

import Foundation
import CoreGraphics
struct OCRTextBox {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    var centerY: CGFloat {
        1.0 - (boundingBox.origin.y + boundingBox.height / 2)
    }
    var centerX: CGFloat {
        boundingBox.origin.x + boundingBox.width / 2
    }
    var minX: CGFloat { boundingBox.origin.x }
    var maxX: CGFloat { boundingBox.origin.x + boundingBox.width }
    var topY: CGFloat { 1.0 - (boundingBox.origin.y + boundingBox.height) }
    var bottomY: CGFloat { 1.0 - boundingBox.origin.y }
}

struct OCRRow {
    var boxes: [OCRTextBox]
    var averageY: CGFloat
}

struct BillLineItem {
    var qty: String
    var particulars: String
    var rate: String?
    var amount: String?
}

struct ParsedBillStructure {
    var items: [BillLineItem]
    var grandTotal: String?
    var footerText: [String]
    var rawText: String
}
