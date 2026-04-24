//  Spatial column parser for bills: uses OCR bounding boxes to reconstruct
//  table structure (Qty | Particulars | Rate | Amount) by geometry.
//  Works for Hindi/English/Hinglish, printed/handwritten.

import Foundation
import CoreGraphics

/// Parsed purchase line item
struct ParsedPurchaseItem {
    var name: String
    var quantity: String
    var unit: String?
    var costPrice: String?
    var sellingPrice: String?
    /// When item not in inventory: only include if likelihood >= this (0...1).
    var itemLikelihood: Double?
    var hsnCode: String?
    var gstRate: String?
}

/// Result of parsing a purchase bill
struct ParsedPurchaseResult {
    var supplierName: String?
    var supplierGSTIN: String?
    var invoiceNumber: String?
    var invoiceDate: String?
    var items: [ParsedPurchaseItem]
    var totalCGST: String?
    var totalSGST: String?
    var totalIGST: String?
    var totalTaxableValue: String?
}

final class BillParser {

    static let shared = BillParser()

    /// Hindi (Devanagari) numeral mapping
     let hindiDigits: [Character: Character] = [
        "०": "0", "१": "1", "२": "2", "३": "3", "४": "4",
        "५": "5", "६": "6", "७": "7", "८": "8", "९": "9"
    ]

    /// Keywords that indicate non-item lines (header/footer/totals). Lowercased.
     let nonItemKeywords: Set<String> = [
        "total", "subtotal", "grand", "gst", "tax", "discount", "amount", "payable",
        "bill", "invoice", "receipt", "date", "no.", "thank", "thanks",
        "rupees", "only", "cash", "card", "visa", "round", "off",
        "service charge", "service", "charge", "cgst", "sgst", "igst", "vat",
        "s.no", "sr.no", "s no", "sr no", "serial", "क्रम",
        "कुल", "जमा", "बिल", "तारीख", "धन्यवाद", "रुपए", "योग",
        "dated", "m/s", "मैसर्स"
    ]

    /// Column header keywords mapped to column type.
     let headerKeywords: [String: ColumnType] = [
        "s.no": .serial, "s.no.": .serial, "s no": .serial, "sno": .serial,
        "sr": .serial, "sr.": .serial, "sr no": .serial, "srno": .serial,
        "sr.no": .serial, "sr.no.": .serial, "serial": .serial,
        "क्र.सं.": .serial, "क्रसं": .serial, "क्रम": .serial,
        // Qty variants
        "qty": .qty, "qty.": .qty, "quantity": .qty, "qnty": .qty,
        "no": .qty, "no.": .qty,
        "मात्रा": .qty, "नग": .qty, "संख्या": .qty,
        // Particulars variants
        "particulars": .particulars, "particular": .particulars, "description": .particulars,
        "item": .particulars, "items": .particulars, "product": .particulars, "name": .particulars, "articles": .particulars,
        "विवरण": .particulars, "सामान": .particulars, "माल": .particulars, "नाम": .particulars,
        // Rate variants
        "rate": .rate, "price": .rate, "mrp": .rate, "unit": .rate,
        "unit price": .rate, "each": .rate,
        "दर": .rate, "भाव": .rate, "रेट": .rate, "rs": .rate, "rs.": .rate,
        // Amount variants
        "amount": .amount, "amt": .amount, "amt.": .amount, "total": .amount,
        "रकम": .amount, "राशि": .amount, "कीमत": .amount, "योग": .amount
    ]

    /// Footer-like keywords
     let footerKeywords: Set<String> = [
        "total", "grand total", "subtotal", "thanking", "thank you", "thanking you",
        "round off", "net amount", "payable", "हस्ताक्षर", "signature",
        "बिका", "वापिस", "भूल", "चूक", "कुल योग", "कुल",
        "% tax", "% service", "gst", "cgst", "sgst"
    ]

     enum ColumnType: String {
        case serial, qty, particulars, rate, amount
    }

     init() {}

    // MARK: ─── Spatial Parsing (Primary) ───────────────────────────────

    /// Parse OCR boxes for sale using spatial column detection.
    func parseForSale(boxes: [OCRTextBox]) -> ParsedResult {
        let bill = parseBillSpatial(boxes: boxes)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        InventoryMatcher.shared.indexInventory(inventory)

        let rawProducts: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = bill.items.map {
            let (q, u) = extractQtyAndUnit($0.qty)
            return (name: $0.particulars, quantity: q, unit: u ?? "pcs", price: cleanPrice($0.rate ?? $0.amount), costPrice: nil)
        }

        // If spatial parsing found items, use them; otherwise fall back to text parsing
        guard !rawProducts.isEmpty else {
            return parseForSale(fullText: bill.rawText)
        }

        // Match against inventory — but keep ALL items, matched or not
        let matched = InventoryMatcher.shared.matchProducts(
            products: rawProducts,
            items: inventory
        )

        let productsForResult: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = matched.map {
            return (name: $0.name, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil)
        }

        for p in productsForResult {
        }

        return ParsedResult(
            entities: [],
            products: productsForResult,
            customerName: nil,
            isNegation: false,
            isReference: false,
            productItemIDs: nil,
            productConfidences: nil
        )
    }

    /// Parse OCR boxes for purchase using spatial column detection.
    func parseForPurchase(boxes: [OCRTextBox]) -> ParsedPurchaseResult {
        let bill = parseBillSpatial(boxes: boxes)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        InventoryMatcher.shared.indexInventory(inventory)

        // If spatial parsing found no items, fall back to text parsing
        guard !bill.items.isEmpty else {
            return parseForPurchase(fullText: bill.rawText)
        }

        var items: [ParsedPurchaseItem] = []

        for lineItem in bill.items {
            let name = lineItem.particulars
            let (qty, unit) = extractQtyAndUnit(lineItem.qty)
            let price = cleanPrice(lineItem.rate ?? lineItem.amount)

            if let match = InventoryMatcher.shared.match(name: name, against: inventory) {
                items.append(ParsedPurchaseItem(
                    name: match.item.name,
                    quantity: qty,
                    unit: unit ?? match.item.unit,
                    costPrice: price,
                    sellingPrice: nil,
                    itemLikelihood: match.confidence
                ))
            } else {
                // Include ALL items — even unmatched ones
                let likelihood = itemLikelihood(name: name, quantity: qty, price: price)
                items.append(ParsedPurchaseItem(
                    name: name,
                    quantity: qty,
                    unit: unit ?? "pcs",
                    costPrice: price,
                    sellingPrice: nil,
                    itemLikelihood: max(likelihood, 0.5)
                ))
            }
        }

        return ParsedPurchaseResult(
            supplierName: nil,
            supplierGSTIN: nil,
            invoiceNumber: nil,
            invoiceDate: nil,
            items: items,
            totalCGST: nil,
            totalSGST: nil,
            totalIGST: nil,
            totalTaxableValue: nil
        )
    }

    // MARK: ─── Core Spatial Algorithm ──────────────────────────────────

    /// Main spatial parsing: boxes → rows → columns → structured bill.
    func parseBillSpatial(boxes: [OCRTextBox]) -> ParsedBillStructure {
        guard !boxes.isEmpty else {
            return ParsedBillStructure(items: [], grandTotal: nil, footerText: [], rawText: "")
        }

        let rawText = boxes.map { $0.text }.joined(separator: "\n")

        // Deskew box coordinates if the receipt was tilted
        let correctedBoxes = deskewBoxes(boxes)
        
        let rows = groupIntoRows(boxes: correctedBoxes)

        let (headerIdx, keywordColumns) = detectColumns(rows: rows)

        var columns: [ColumnType: CGFloat]
        var dataStartRow: Int

        let validKeywordCols = validateColumns(keywordColumns)

        if validKeywordCols.count >= 2 {
            columns = validKeywordCols
            dataStartRow = (headerIdx ?? 0) + 1
        } else {
            // Geometric column detection — works with ANY headers or no headers
            let (geoCols, skipRows) = detectColumnsGeometric(rows: rows)
            if !geoCols.isEmpty {
                columns = geoCols
                dataStartRow = skipRows
            } else if !keywordColumns.isEmpty {
                // Fall back to whatever keywords found
                columns = keywordColumns
                dataStartRow = (headerIdx ?? 0) + 1
            } else {
                return parseFallbackPositional(rows: rows, rawText: rawText)
            }
        }

        var items: [BillLineItem] = []
        var grandTotal: String?
        var footerText: [String] = []
        var inFooter = false

        for rowIdx in dataStartRow..<rows.count {
            let row = rows[rowIdx]
            let rowText = row.boxes.map { $0.text }.joined(separator: " ").lowercased()

            if isFooterRow(rowText) {
                inFooter = true
                if let total = extractTotal(from: row) {
                    grandTotal = total
                }
                let ft = row.boxes.map { $0.text }.joined(separator: " ")
                if !ft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    footerText.append(ft)
                }
                continue
            }

            if inFooter {
                let ft = row.boxes.map { $0.text }.joined(separator: " ")
                if !ft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    footerText.append(ft)
                }
                continue
            }

            // Assign boxes to columns
            if let item = assignBoxesToColumns(row: row, columns: columns) {
                items.append(item)
            }
        }

        return ParsedBillStructure(items: items, grandTotal: grandTotal, footerText: footerText, rawText: rawText)
    }

    // MARK: ─── Geometric Column Detection ─────────────────────────────

    /// Detect columns by analyzing X-position patterns across all rows.
    /// Works without any header keywords — purely structural.
    /// Returns (column map, first data row index).
     func detectColumnsGeometric(rows: [OCRRow]) -> ([ColumnType: CGFloat], Int) {
        guard rows.count >= 3 else { return ([:], 0) }

        var xPositions: [[CGFloat]] = []  // Each inner array = X positions of boxes in one row
        var tabularRowIndices: [Int] = []

        for (idx, row) in rows.enumerated() {
            if row.boxes.count >= 2 {
                let xs = row.boxes.map { $0.centerX }.sorted()
                xPositions.append(xs)
                tabularRowIndices.append(idx)
            }
        }

        guard xPositions.count >= 2 else { return ([:], 0) }

        let colCounts = xPositions.map { $0.count }
        let mostCommon = colCounts.sorted().count > 0 ?
            Dictionary(grouping: colCounts, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key ?? 0 : 0

        guard mostCommon >= 2 else { return ([:], 0) }

        let dataRows = zip(xPositions, tabularRowIndices).filter { $0.0.count == mostCommon }
        guard !dataRows.isEmpty else { return ([:], 0) }

        var avgX: [CGFloat] = Array(repeating: 0, count: mostCommon)
        for (xs, _) in dataRows {
            for (i, x) in xs.enumerated() {
                avgX[i] += x
            }
        }
        avgX = avgX.map { $0 / CGFloat(dataRows.count) }

        var colTypes: [ColumnType: CGFloat] = [:]

        for colIdx in 0..<mostCommon {
            var numericCount = 0
            var textCount = 0
            var avgValue: Double = 0
            var valueCount = 0

            for (_, rowIdx) in dataRows {
                let row = rows[rowIdx]
                let sorted = row.boxes.sorted { $0.centerX < $1.centerX }
                guard colIdx < sorted.count else { continue }

                let box = sorted[colIdx]
                if looksNumeric(box.text) {
                    numericCount += 1
                    if let val = Double(cleanPrice(box.text) ?? "") {
                        avgValue += val
                        valueCount += 1
                    }
                } else {
                    textCount += 1
                }
            }

            let avg = valueCount > 0 ? avgValue / Double(valueCount) : 0

            if textCount > numericCount {
                // Mostly text → particulars
                if colTypes[.particulars] == nil {
                    colTypes[.particulars] = avgX[colIdx]
                }
            } else {
                // Mostly numbers
                if avg < 100 && colTypes[.qty] == nil {
                    colTypes[.qty] = avgX[colIdx]
                } else if colTypes[.amount] == nil && colIdx == mostCommon - 1 {
                    // Rightmost numeric column → amount
                    colTypes[.amount] = avgX[colIdx]
                } else if colTypes[.rate] == nil {
                    colTypes[.rate] = avgX[colIdx]
                } else if colTypes[.amount] == nil {
                    colTypes[.amount] = avgX[colIdx]
                }
            }
        }

        let firstDataRow = dataRows.first?.1 ?? 0
        // Header is likely the row before first data row, or row with non-item text
        let startRow = max(0, firstDataRow)

        for (type, x) in colTypes.sorted(by: { $0.value < $1.value }) {
        }

        return (colTypes, startRow)
    }

    // MARK: ─── Coordinate Deskew ───────────────────────────────────────
    
    /// Detects the dominant text line slope from OCR box coordinates and
    /// creates new OCRTextBox objects with rotated bounding boxes.
    /// This fixes row grouping when the receipt image is slightly tilted.
     func deskewBoxes(_ boxes: [OCRTextBox]) -> [OCRTextBox] {
        guard boxes.count >= 4 else { return boxes }
        
        // Pair boxes that are horizontally adjacent (same row candidates)
        // and compute the slope between their centers
        let sorted = boxes.sorted { $0.centerY < $1.centerY }
        var angles: [CGFloat] = []
        
        // Find boxes that are roughly on the same line
        let medianHeight = boxes.map { $0.boundingBox.height }.sorted()[boxes.count / 2]
        let yTolerance = medianHeight * 1.5
        
        for i in 0..<sorted.count {
            for j in (i+1)..<min(i+5, sorted.count) {
                let a = sorted[i]
                let b = sorted[j]
                
                // Check if they are on roughly the same row
                guard abs(a.centerY - b.centerY) < yTolerance else { continue }
                
                // Need meaningful horizontal separation
                let dx = b.centerX - a.centerX
                let dy = b.centerY - a.centerY
                guard abs(dx) > 0.05 else { continue }
                
                let angle = atan2(dy, dx)
                // Only consider small angles (< 25°)
                if abs(angle) < 0.44 { // ~25 degrees in radians
                    angles.append(angle)
                }
            }
        }
        
        guard angles.count >= 3 else { return boxes }
        
        // Compute median angle
        let sortedAngles = angles.sorted()
        let medianAngle = sortedAngles[sortedAngles.count / 2]
        let angleDegrees = medianAngle * 180.0 / .pi
        
        // Only correct if tilt is significant (> 0.5°) but reasonable (< 20°)
        guard abs(angleDegrees) > 0.5 && abs(angleDegrees) < 20.0 else {
            return boxes
        }
        
        print("[BillParser] Deskewing box coordinates by \(String(format: "%.1f", angleDegrees))°")
        
        // Rotate all box coordinates by -medianAngle around the image center (0.5, 0.5)
        let cosA = cos(-medianAngle)
        let sinA = sin(-medianAngle)
        let cx: CGFloat = 0.5
        let cy: CGFloat = 0.5
        
        return boxes.map { box in
            let origCenterX = box.boundingBox.midX
            let origCenterY = box.boundingBox.midY
            
            // Translate to origin, rotate, translate back
            let dx = origCenterX - cx
            let dy = origCenterY - cy
            let newCX = dx * cosA - dy * sinA + cx
            let newCY = dx * sinA + dy * cosA + cy
            
            // Reconstruct bounding box centered at new position
            let newOriginX = newCX - box.boundingBox.width / 2
            let newOriginY = newCY - box.boundingBox.height / 2
            let newRect = CGRect(
                x: newOriginX,
                y: newOriginY,
                width: box.boundingBox.width,
                height: box.boundingBox.height
            )
            
            return OCRTextBox(
                text: box.text,
                boundingBox: newRect,
                confidence: box.confidence
            )
        }
    }

    // MARK: ─── Row Grouping ───────────────────────────────────────────

    /// Group boxes into rows by Y-coordinate proximity.
    /// Uses adaptive tolerance based on actual box heights.
     func groupIntoRows(boxes: [OCRTextBox]) -> [OCRRow] {
        guard !boxes.isEmpty else { return [] }

        // Compute adaptive Y-tolerance from median box height
        let heights = boxes.map { $0.boundingBox.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        // Tolerance = half the median box height (boxes on the same line overlap in Y)
        let yTolerance = max(medianHeight * 0.6, 0.005)

        let sorted = boxes.sorted { $0.topY < $1.topY }

        var rows: [OCRRow] = []
        var currentBoxes: [OCRTextBox] = [sorted[0]]
        var currentAvgY = sorted[0].centerY

        for box in sorted.dropFirst() {
            if abs(box.centerY - currentAvgY) <= yTolerance {
                currentBoxes.append(box)
                currentAvgY = currentBoxes.map { $0.centerY }.reduce(0, +) / CGFloat(currentBoxes.count)
            } else {
                rows.append(OCRRow(
                    boxes: currentBoxes.sorted { $0.centerX < $1.centerX },
                    averageY: currentAvgY
                ))
                currentBoxes = [box]
                currentAvgY = box.centerY
            }
        }
        // Last row
        rows.append(OCRRow(
            boxes: currentBoxes.sorted { $0.centerX < $1.centerX },
            averageY: currentAvgY
        ))

        return rows
    }

    // MARK: ─── Column Detection ───────────────────────────────────────

    /// Normalize text for header keyword matching: lowercase, strip periods, trim.
     func normalizeForMatch(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove columns that overlap (within 5% X distance), keeping the more important one.
     func validateColumns(_ cols: [ColumnType: CGFloat]) -> [ColumnType: CGFloat] {
        let priority: [ColumnType: Int] = [.particulars: 4, .amount: 3, .rate: 2, .qty: 1]
        var valid: [ColumnType: CGFloat] = [:]
        let sorted = cols.sorted { (priority[$0.key] ?? 0) > (priority[$1.key] ?? 0) }

        for (type, x) in sorted {
            let overlaps = valid.values.contains { abs($0 - x) < 0.05 }
            if !overlaps {
                valid[type] = x
            } else {
            }
        }
        return valid
    }

    /// Find header row and extract column X-positions.
     func detectColumns(rows: [OCRRow]) -> (headerIndex: Int?, columns: [ColumnType: CGFloat]) {
        for (idx, row) in rows.enumerated() {
            var found: [ColumnType: CGFloat] = [:]

            for box in row.boxes {
                let normalized = normalizeForMatch(box.text)

                // Check the full normalized text first
                if let colType = headerKeywords[normalized], found[colType] == nil {
                    found[colType] = box.centerX
                    continue
                }

                // Check each word individually
                let words = normalized.split(separator: " ").map(String.init)
                for word in words {
                    if let colType = headerKeywords[word], found[colType] == nil {
                        found[colType] = box.centerX
                    }
                }

                // Also check with periods intact (e.g. "s.no", "qty.", "amt.")
                let lowerDotted = box.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if let colType = headerKeywords[lowerDotted], found[colType] == nil {
                    found[colType] = box.centerX
                }

                // Check combined adjacent words (e.g. "s no" → "s.no")
                let joined = words.joined()
                if let colType = headerKeywords[joined], found[colType] == nil {
                    found[colType] = box.centerX
                }
            }

            // Need at least 2 columns detected to consider this a header
            if found.count >= 2 {
                return (idx, found)
            }
        }
        return (nil, [:])
    }

    // MARK: ─── Column Assignment ──────────────────────────────────────

    /// Assign a row's boxes to the detected columns by X-position proximity.
     func assignBoxesToColumns(row: OCRRow, columns: [ColumnType: CGFloat]) -> BillLineItem? {
        guard !row.boxes.isEmpty else { return nil }

        let sortedCols = columns.sorted { $0.value < $1.value }

        var assignments: [ColumnType: String] = [:]

        for box in row.boxes {
            var bestCol: ColumnType?
            var bestDist: CGFloat = .greatestFiniteMagnitude

            for (colType, colX) in sortedCols {
                let dist = abs(box.centerX - colX)
                if dist < bestDist {
                    bestDist = dist
                    bestCol = colType
                }
            }

            // Only assign if reasonably close (within 15% of image width)
            if let col = bestCol, bestDist < 0.15 {
                if let existing = assignments[col] {
                    assignments[col] = existing + " " + box.text
                } else {
                    assignments[col] = box.text
                }
            } else {
                // Box too far from any column — try to assign by content type
                if looksNumeric(box.text) {
                    // Assign to rate or amount (whichever is missing)
                    if assignments[.amount] == nil && columns[.amount] != nil {
                        assignments[.amount] = box.text
                    } else if assignments[.rate] == nil && columns[.rate] != nil {
                        assignments[.rate] = box.text
                    } else if assignments[.amount] == nil {
                        assignments[.amount] = box.text
                    }
                } else if assignments[.particulars] == nil {
                    assignments[.particulars] = box.text
                } else {
                    // Append to particulars
                    assignments[.particulars] = (assignments[.particulars] ?? "") + " " + box.text
                }
            }
        }

        let particulars = assignments[.particulars]?.trimmingCharacters(in: .whitespaces) ?? ""
        let qty = assignments[.qty]?.trimmingCharacters(in: .whitespaces) ?? "1"
        // IGNORE .serial column — it's just S.No (1., 2., 3.) not actual quantity

        guard !particulars.isEmpty else { return nil }
        let lowerPart = particulars.lowercased()
        if nonItemKeywords.contains(where: { lowerPart.contains($0) }) { return nil }

        return BillLineItem(
            qty: qty,
            particulars: particulars,
            rate: assignments[.rate]?.trimmingCharacters(in: .whitespaces),
            amount: assignments[.amount]?.trimmingCharacters(in: .whitespaces)
        )
    }

    // MARK: ─── Positional Fallback ────────────────────────────────────

    /// When no header is detected: use positional heuristics.
    /// Separates each row into numeric parts (qty, rate, amount) and text parts (item name).
     func parseFallbackPositional(rows: [OCRRow], rawText: String) -> ParsedBillStructure {
        var items: [BillLineItem] = []
        var grandTotal: String?
        var footerText: [String] = []
        var inFooter = false

        let skipRows = min(2, rows.count > 4 ? 2 : 0)

        for (rowIdx, row) in rows.enumerated() {
            let rowText = row.boxes.map { $0.text }.joined(separator: " ").lowercased()

            if rowIdx < skipRows && !containsItemLikeContent(rowText) { continue }

            if isFooterRow(rowText) {
                inFooter = true
                if let total = extractTotal(from: row) { grandTotal = total }
                footerText.append(row.boxes.map { $0.text }.joined(separator: " "))
                continue
            }
            if inFooter {
                footerText.append(row.boxes.map { $0.text }.joined(separator: " "))
                continue
            }

            let sorted = row.boxes.sorted { $0.centerX < $1.centerX }

            // Separate into numeric and text boxes
            let numericBoxes = sorted.filter { looksNumeric($0.text) }
            let textBoxes = sorted.filter { !looksNumeric($0.text) }

            var qty = "1"
            var name = ""
            var rate: String?
            var amount: String?

            // Extract qty: leftmost numeric box (if small number, likely qty)
            if let firstNum = numericBoxes.first {
                let qtyCandidate = cleanPrice(firstNum.text)
                if let val = Double(qtyCandidate ?? ""), val < 500 {
                    qty = qtyCandidate ?? "1"
                }
            }

            // Extract rate/amount from rightmost numeric boxes
            if numericBoxes.count >= 3 {
                rate = cleanPrice(numericBoxes[numericBoxes.count - 2].text)
                amount = cleanPrice(numericBoxes.last!.text)
            } else if numericBoxes.count >= 2 {
                amount = cleanPrice(numericBoxes.last!.text)
            } else if numericBoxes.count == 1 && textBoxes.isEmpty {
                // Single number row — skip (it's probably a total or serial #)
                continue
            }

            // Name = all text (non-numeric) boxes
            name = textBoxes.map { $0.text }.joined(separator: " ")

            // If no text boxes but multiple numeric boxes, middle ones might be name
            if name.isEmpty && sorted.count >= 3 {
                // Try the second box as name (between qty and price)
                let middleBoxes = sorted.dropFirst().dropLast()
                let middleText = middleBoxes.filter { !looksNumeric($0.text) }
                if !middleText.isEmpty {
                    name = middleText.map { $0.text }.joined(separator: " ")
                }
            }

            // Handle single-box rows: try to split "2 Parle G 10" pattern
            if sorted.count == 1 {
                let parts = sorted[0].text.split(separator: " ").map(String.init)
                if parts.count >= 2 {
                    let numParts = parts.filter { looksNumeric($0) }
                    let textParts = parts.filter { !looksNumeric($0) }
                    if !textParts.isEmpty {
                        name = textParts.joined(separator: " ")
                        if let first = numParts.first, let val = Double(cleanPrice(first) ?? ""), val < 500 {
                            qty = cleanPrice(first) ?? "1"
                        }
                        if numParts.count >= 2 {
                            amount = cleanPrice(numParts.last!)
                        }
                    } else {
                        continue // All-numeric single box, skip
                    }
                } else {
                    // Single word in single box — probably not an item
                    continue
                }
            }

            name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let lowerName = name.lowercased()
            if nonItemKeywords.contains(where: { lowerName.contains($0) }) { continue }

            items.append(BillLineItem(qty: qty, particulars: name, rate: rate, amount: amount))
        }

        return ParsedBillStructure(items: items, grandTotal: grandTotal, footerText: footerText, rawText: rawText)
    }

    /// Check if row text looks like it could contain item data (has numbers + text).
     func containsItemLikeContent(_ text: String) -> Bool {
        let hasNumbers = text.contains(where: { $0.isNumber })
        let hasLetters = text.contains(where: { $0.isLetter })
        return hasNumbers && hasLetters
    }

    // MARK: ─── Helpers ────────────────────────────────────────────────

     func isFooterRow(_ text: String) -> Bool {
        let lower = text.lowercased()
        return footerKeywords.contains(where: { lower.contains($0) })
    }

     func extractTotal(from row: OCRRow) -> String? {
        for box in row.boxes {
            if looksNumeric(box.text) && !box.text.lowercased().contains("total") {
                return cleanPrice(box.text)
            }
        }
        return nil
    }

     func looksNumeric(_ text: String) -> Bool {
        let converted = convertHindiNumerals(text)
        let stripped = converted
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "/-", with: "")
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "Rs", with: "")
            .replacingOccurrences(of: "rs", with: "")
        let digits = stripped.filter { $0.isNumber || $0 == "." || $0 == "/" }
        return !digits.isEmpty && Double(digits.replacingOccurrences(of: "/", with: "")) != nil
    }

    /// Convert Devanagari numerals (१२३) to Arabic (123).
     func convertHindiNumerals(_ text: String) -> String {
        var result = ""
        for char in text {
            if let arabic = hindiDigits[char] {
                result.append(arabic)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Extract numeric quantity AND unit from strings like "10 kg", "5kg", "२/१०".
     func extractQtyAndUnit(_ qtyStr: String) -> (number: String, unit: String?) {
        var cleaned = convertHindiNumerals(qtyStr)
            .trimmingCharacters(in: .whitespaces)
        
        var foundUnit: String? = nil
        
        // Strip common unit words and capture the first one found
        let unitWords = ["kg", "kgs", "litre", "litres", "ltr", "pz", "pc", "pcs", "pieces",
                         "gm", "gms", "gram", "grams", "ml", "lbs", "lb", "ton", "tons",
                         "tire", "kz", "meter", "mtr", "ft", "dozen"]
        
        for unit in unitWords {
            if cleaned.lowercased().contains(unit) {
                foundUnit = unit
                cleaned = cleaned.replacingOccurrences(of: unit, with: "", options: .caseInsensitive)
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if let slashIdx = cleaned.firstIndex(of: "/") {
            let before = String(cleaned[cleaned.startIndex..<slashIdx]).trimmingCharacters(in: .whitespaces)
            let after = String(cleaned[cleaned.index(after: slashIdx)...]).trimmingCharacters(in: .whitespaces)
            let numerator = before.filter { $0.isNumber || $0 == "." }
            let denominator = after.filter { $0.isNumber || $0 == "." }

            if let num = Double(numerator), let den = Double(denominator), den > 0, den <= 10, num < den {
                let result = num / den
                return (number: result == result.rounded() ? String(Int(result)) : String(format: "%.1f", result), unit: foundUnit)
            }
            return (number: numerator.isEmpty ? "1" : numerator, unit: foundUnit)
        }
        let digits = cleaned.filter { $0.isNumber || $0 == "." }
        return (number: digits.isEmpty ? "1" : digits, unit: foundUnit)
    }

    /// Clean price string: "44/-" → "44", "$2.00/kg" → "2.00", "₹50" → "50", "१२७" → "127"
     func cleanPrice(_ priceStr: String?) -> String? {
        guard var p = priceStr?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return nil }
        p = convertHindiNumerals(p)
        // Strip currency symbols
        p = p.replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "Rs.", with: "")
            .replacingOccurrences(of: "Rs", with: "")
            .replacingOccurrences(of: "/-", with: "")
            .replacingOccurrences(of: ",", with: "")
        // Strip unit suffixes like /kg, /kB, /unit, /pcs, /litre
        if let slashUnit = p.range(of: "/[a-zA-Z]+", options: .regularExpression) {
            p = String(p[p.startIndex..<slashUnit.lowerBound])
        }
        p = p.trimmingCharacters(in: .whitespaces)
        if let dashIdx = p.firstIndex(of: "-"), dashIdx != p.startIndex {
            let before = String(p[p.startIndex..<dashIdx])
            let after = String(p[p.index(after: dashIdx)...])
            if before.allSatisfy({ $0.isNumber }) && after.allSatisfy({ $0.isNumber }) {
                p = before + "." + after
            }
        }
        return p.isEmpty ? nil : p
    }

    /// Score how likely this is a real product (not "Total", "GST", etc.).
     func itemLikelihood(name: String, quantity: String, price: String?) -> Double {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        let tokens = lower.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        if lower.isEmpty || tokens.isEmpty { return 0 }
        if tokens.count == 1 && tokens[0].allSatisfy({ $0.isNumber || $0 == "." }) { return 0 }
        if nonItemKeywords.contains(where: { lower.contains($0) }) { return 0 }

        var score = 0.5
        let hasQty = Int(quantity.filter { $0.isNumber }) != nil
        let hasPrice = price.flatMap { Double($0.filter { $0.isNumber || $0 == "." }) } != nil
        if hasQty { score += 0.2 }
        if hasPrice ?? false { score += 0.15 }
        let hasNonNumeric = tokens.contains { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        if hasNonNumeric { score += 0.15 }
        if tokens.count >= 2 { score += 0.1 }

        return min(1.0, score)
    }

    // MARK: ─── Legacy Text-Only Parsing (Fallback) ────────────────────

    /// Legacy: parse flat text for sale (used as fallback when spatial parsing fails).
    func parseForSale(fullText: String) -> ParsedResult {
        let rawProducts = extractProductsFromBill(fullText)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []

        InventoryMatcher.shared.indexInventory(inventory)

        let matched = InventoryMatcher.shared.matchProducts(
            products: rawProducts.map { (name: $0.name, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil as String?) },
            items: inventory
        )

        let minConfidence = 0.35
        let productsForResult = matched
            .filter { $0.matchConfidence >= minConfidence }
            .map { (name: $0.name, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil as String?) }

        return ParsedResult(
            entities: [],
            products: productsForResult.isEmpty && !rawProducts.isEmpty
                ? rawProducts.map { (name: $0.name, quantity: $0.quantity, unit: $0.unit, price: $0.price, costPrice: nil as String?) }
                : productsForResult,
            customerName: nil,
            isNegation: false,
            isReference: false,
            productItemIDs: nil,
            productConfidences: nil
        )
    }

    /// Legacy: parse flat text for purchase.
    func parseForPurchase(fullText: String) -> ParsedPurchaseResult {
        let rawProducts = extractProductsFromBill(fullText)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        InventoryMatcher.shared.indexInventory(inventory)

        let minNewItemLikelihood = 0.55
        var items: [ParsedPurchaseItem] = []

        for p in rawProducts {
            if let match = InventoryMatcher.shared.match(name: p.name, against: inventory) {
                items.append(ParsedPurchaseItem(
                    name: match.item.name,
                    quantity: p.quantity,
                    unit: p.unit ?? match.item.unit,
                    costPrice: p.price,
                    sellingPrice: nil,
                    itemLikelihood: match.confidence
                ))
            } else {
                let likelihood = itemLikelihood(name: p.name, quantity: p.quantity, price: p.price)
                if likelihood >= minNewItemLikelihood {
                    items.append(ParsedPurchaseItem(
                        name: p.name,
                        quantity: p.quantity,
                        unit: p.unit,
                        costPrice: p.price,
                        sellingPrice: nil,
                        itemLikelihood: likelihood
                    ))
                }
            }
        }

        return ParsedPurchaseResult(
            supplierName: nil,
            supplierGSTIN: nil,
            invoiceNumber: nil,
            invoiceDate: nil,
            items: items,
            totalCGST: nil,
            totalSGST: nil,
            totalIGST: nil,
            totalTaxableValue: nil
        )
    }

    /// Extract products from flat text (legacy line-by-line regex).
     func extractProductsFromBill(_ text: String) -> [(name: String, quantity: String, unit: String?, price: String?)] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let itemLines = itemLinesOnly(lines)
        var products: [(name: String, quantity: String, unit: String?, price: String?)] = []

        for line in itemLines {
            if let parsed = parseLineAsItem(line) {
                products.append(parsed)
            }
        }

        return products.isEmpty ? [(name: text, quantity: "1", unit: "pcs", price: nil)] : products
    }

    /// Filter to lines that look like items (skip header/footer/totals).
     func itemLinesOnly(_ lines: [String]) -> [String] {
        if lines.isEmpty { return [] }
        var start = 0
        var end = lines.count
        let sectionStart: Set<String> = ["item", "items", "particulars", "description", "sr", "product", "products", "s.no", "s no"]
        let sectionEnd: Set<String> = ["total", "subtotal", "grand total", "net amount", "payable", "round off"]

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let firstWord = lower.split(separator: " ").first.map(String.init) ?? ""
            if sectionStart.contains(firstWord) || sectionStart.contains(where: { lower.hasPrefix($0) }) {
                start = min(i + 1, lines.count)
            }
            if sectionEnd.contains(where: { lower.contains($0) }) {
                end = i; break
            }
        }

        return Array(lines[start..<end]).filter { line in
            !isNonItemLine(line)
        }
    }

     func isNonItemLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let tokens = lower.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if tokens.isEmpty { return true }
        if tokens.count == 1 {
            return tokens[0].allSatisfy { $0.isNumber || $0 == "." } || nonItemKeywords.contains(tokens[0])
        }
        if nonItemKeywords.contains(where: { lower.contains($0) }) { return true }
        let onlyNumbers = tokens.allSatisfy { $0.filter({ $0.isNumber }).count == $0.count }
        return onlyNumbers
    }

    /// Try multiple patterns: "qty name price", "name qty price", etc.
     func parseLineAsItem(_ line: String) -> (name: String, quantity: String, unit: String?, price: String?)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 1 else { return nil }

        var qty = "1"
        var name = ""
        var unit: String? = "pcs"
        var price: String?

        let numIndices = tokens.enumerated().compactMap { i, t -> (Int, String)? in
            let digits = t.filter { $0.isNumber }
            if !digits.isEmpty { return (i, String(digits)) }
            return nil
        }

        if numIndices.isEmpty {
            name = line
            return name.count > 1 ? (name, qty, unit, price) : nil
        }

        let firstNum = numIndices[0]
        let lastNum = numIndices.last!

        qty = firstNum.1
        if numIndices.count >= 2 {
            price = lastNum.1
            if firstNum.0 == 0 {
                name = tokens[1..<lastNum.0].joined(separator: " ")
            } else {
                name = tokens[0..<firstNum.0].joined(separator: " ")
            }
            if name.isEmpty && lastNum.0 > firstNum.0 + 1 {
                name = tokens[(firstNum.0 + 1)..<lastNum.0].joined(separator: " ")
            }
        } else {
            name = firstNum.0 == 0 ? tokens.dropFirst().joined(separator: " ") : tokens.prefix(firstNum.0).joined(separator: " ")
        }

        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }
        if name.count < 2 { return nil }
        if nonItemKeywords.contains(where: { name.lowercased().contains($0) }) { return nil }

        return (name, qty, unit, price)
    }
}
