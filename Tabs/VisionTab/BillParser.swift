
import Foundation
import CoreGraphics

struct ParsedPurchaseItem {
    var name: String
    var quantity: String
    var unit: String?
    var costPrice: String?
    var sellingPrice: String?
    var itemLikelihood: Double?
    var hsnCode: String?
    var gstRate: String?
}

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

     let hindiDigits: [Character: Character] = [
        "०": "0", "१": "1", "२": "2", "३": "3", "४": "4",
        "५": "5", "६": "6", "७": "7", "८": "8", "९": "9"
    ]

     let nonItemKeywords: Set<String> = [
        "total", "subtotal", "grand", "gst", "tax", "discount", "amount", "payable",
        "bill", "invoice", "receipt", "date", "no.", "thank", "thanks",
        "rupees", "only", "cash", "card", "visa", "round", "off",
        "service charge", "service", "charge", "cgst", "sgst", "igst", "vat",
        "s.no", "sr.no", "s no", "sr no", "serial", "क्रम",
        "कुल", "जमा", "बिल", "तारीख", "धन्यवाद", "रुपए", "योग",
        "dated", "m/s", "मैसर्स"
    ]

     let headerKeywords: [String: ColumnType] = [
        "s.no": .serial, "s.no.": .serial, "s no": .serial, "sno": .serial,
        "sr": .serial, "sr.": .serial, "sr no": .serial, "srno": .serial,
        "sr.no": .serial, "sr.no.": .serial, "serial": .serial,
        "क्र.सं.": .serial, "क्रसं": .serial, "क्रम": .serial,
        "qty": .qty, "qty.": .qty, "quantity": .qty, "qnty": .qty,
        "no": .qty, "no.": .qty,
        "मात्रा": .qty, "नग": .qty, "संख्या": .qty,
        "particulars": .particulars, "particular": .particulars, "description": .particulars,
        "item": .particulars, "items": .particulars, "product": .particulars, "name": .particulars, "articles": .particulars,
        "विवरण": .particulars, "सामान": .particulars, "माल": .particulars, "नाम": .particulars,
        "rate": .rate, "price": .rate, "mrp": .rate, "unit": .rate,
        "unit price": .rate, "each": .rate,
        "दर": .rate, "भाव": .rate, "रेट": .rate, "rs": .rate, "rs.": .rate,
        "amount": .amount, "amt": .amount, "amt.": .amount, "total": .amount,
        "रकम": .amount, "राशि": .amount, "कीमत": .amount, "योग": .amount
    ]

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


    func parseForSale(boxes: [OCRTextBox]) -> ParsedResult {
        let bill = parseBillSpatial(boxes: boxes)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        InventoryMatcher.shared.indexInventory(inventory)

        let rawProducts: [(name: String, quantity: String, unit: String?, price: String?, costPrice: String?)] = bill.items.map {
            let (q, u) = extractQtyAndUnit($0.qty)
            return (name: $0.particulars, quantity: q, unit: u ?? "pcs", price: cleanPrice($0.rate ?? $0.amount), costPrice: nil)
        }

        guard !rawProducts.isEmpty else {
            return parseForSale(fullText: bill.rawText)
        }

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

    func parseForPurchase(boxes: [OCRTextBox]) -> ParsedPurchaseResult {
        let bill = parseBillSpatial(boxes: boxes)
        let inventory = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        InventoryMatcher.shared.indexInventory(inventory)

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


    func parseBillSpatial(boxes: [OCRTextBox]) -> ParsedBillStructure {
        guard !boxes.isEmpty else {
            return ParsedBillStructure(items: [], grandTotal: nil, footerText: [], rawText: "")
        }

        let rawText = boxes.map { $0.text }.joined(separator: "\n")

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
            let (geoCols, skipRows) = detectColumnsGeometric(rows: rows)
            if !geoCols.isEmpty {
                columns = geoCols
                dataStartRow = skipRows
            } else if !keywordColumns.isEmpty {
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

            if let item = assignBoxesToColumns(row: row, columns: columns) {
                items.append(item)
            }
        }

        return ParsedBillStructure(items: items, grandTotal: grandTotal, footerText: footerText, rawText: rawText)
    }


     func detectColumnsGeometric(rows: [OCRRow]) -> ([ColumnType: CGFloat], Int) {
        guard rows.count >= 3 else { return ([:], 0) }

        var xPositions: [[CGFloat]] = []
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
                if colTypes[.particulars] == nil {
                    colTypes[.particulars] = avgX[colIdx]
                }
            } else {
                if avg < 100 && colTypes[.qty] == nil {
                    colTypes[.qty] = avgX[colIdx]
                } else if colTypes[.amount] == nil && colIdx == mostCommon - 1 {
                    colTypes[.amount] = avgX[colIdx]
                } else if colTypes[.rate] == nil {
                    colTypes[.rate] = avgX[colIdx]
                } else if colTypes[.amount] == nil {
                    colTypes[.amount] = avgX[colIdx]
                }
            }
        }

        let firstDataRow = dataRows.first?.1 ?? 0
        let startRow = max(0, firstDataRow)

        for (type, x) in colTypes.sorted(by: { $0.value < $1.value }) {
        }

        return (colTypes, startRow)
    }

    
     func deskewBoxes(_ boxes: [OCRTextBox]) -> [OCRTextBox] {
        guard boxes.count >= 4 else { return boxes }
        
        let sorted = boxes.sorted { $0.centerY < $1.centerY }
        var angles: [CGFloat] = []
        
        let medianHeight = boxes.map { $0.boundingBox.height }.sorted()[boxes.count / 2]
        let yTolerance = medianHeight * 1.5
        
        for i in 0..<sorted.count {
            for j in (i+1)..<min(i+5, sorted.count) {
                let a = sorted[i]
                let b = sorted[j]
                
                guard abs(a.centerY - b.centerY) < yTolerance else { continue }
                
                let dx = b.centerX - a.centerX
                let dy = b.centerY - a.centerY
                guard abs(dx) > 0.05 else { continue }
                
                let angle = atan2(dy, dx)
                if abs(angle) < 0.44 {
                    angles.append(angle)
                }
            }
        }
        
        guard angles.count >= 3 else { return boxes }
        
        let sortedAngles = angles.sorted()
        let medianAngle = sortedAngles[sortedAngles.count / 2]
        let angleDegrees = medianAngle * 180.0 / .pi
        
        guard abs(angleDegrees) > 0.2 && abs(angleDegrees) < 20.0 else {
            return boxes
        }
        
        print("[BillParser] Deskewing box coordinates by \(String(format: "%.1f", angleDegrees))°")
        
        let cosA = cos(-medianAngle)
        let sinA = sin(-medianAngle)
        let cx: CGFloat = 0.5
        let cy: CGFloat = 0.5
        
        return boxes.map { box in
            let origCenterX = box.boundingBox.midX
            let origCenterY = box.boundingBox.midY
            
            let dx = origCenterX - cx
            let dy = origCenterY - cy
            let newCX = dx * cosA - dy * sinA + cx
            let newCY = dx * sinA + dy * cosA + cy
            
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


     func groupIntoRows(boxes: [OCRTextBox]) -> [OCRRow] {
        guard !boxes.isEmpty else { return [] }

        let sorted = boxes.sorted { $0.topY < $1.topY }

        var rows: [OCRRow] = []
        var currentBoxes: [OCRTextBox] = [sorted[0]]
        
        var currentRowTopY = sorted[0].topY
        var currentRowBottomY = sorted[0].bottomY

        for box in sorted.dropFirst() {
            let boxHeight = box.bottomY - box.topY
            let intersectionTop = max(currentRowTopY, box.topY)
            let intersectionBottom = min(currentRowBottomY, box.bottomY)
            let intersectionHeight = max(0, intersectionBottom - intersectionTop)
            
            let rowHeight = currentRowBottomY - currentRowTopY
            let overlapRatioBox = boxHeight > 0 ? intersectionHeight / boxHeight : 0
            let overlapRatioRow = rowHeight > 0 ? intersectionHeight / rowHeight : 0
            
            if overlapRatioBox > 0.3 || overlapRatioRow > 0.3 {
                currentBoxes.append(box)
                currentRowTopY = min(currentRowTopY, box.topY)
                currentRowBottomY = max(currentRowBottomY, box.bottomY)
            } else {
                let currentAvgY = currentBoxes.map { $0.centerY }.reduce(0, +) / CGFloat(currentBoxes.count)
                rows.append(OCRRow(
                    boxes: currentBoxes.sorted { $0.centerX < $1.centerX },
                    averageY: currentAvgY
                ))
                currentBoxes = [box]
                currentRowTopY = box.topY
                currentRowBottomY = box.bottomY
            }
        }
        let currentAvgY = currentBoxes.map { $0.centerY }.reduce(0, +) / CGFloat(currentBoxes.count)
        rows.append(OCRRow(
            boxes: currentBoxes.sorted { $0.centerX < $1.centerX },
            averageY: currentAvgY
        ))

        return rows
    }


     func normalizeForMatch(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

     func detectColumns(rows: [OCRRow]) -> (headerIndex: Int?, columns: [ColumnType: CGFloat]) {
        for (idx, row) in rows.enumerated() {
            var found: [ColumnType: CGFloat] = [:]

            for box in row.boxes {
                let normalized = normalizeForMatch(box.text)

                if let colType = headerKeywords[normalized], found[colType] == nil {
                    found[colType] = box.centerX
                    continue
                }

                let words = normalized.split(separator: " ").map(String.init)
                for word in words {
                    if let colType = headerKeywords[word], found[colType] == nil {
                        found[colType] = box.centerX
                    }
                }

                let lowerDotted = box.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if let colType = headerKeywords[lowerDotted], found[colType] == nil {
                    found[colType] = box.centerX
                }

                let joined = words.joined()
                if let colType = headerKeywords[joined], found[colType] == nil {
                    found[colType] = box.centerX
                }
            }

            if found.count >= 2 {
                return (idx, found)
            }
        }
        return (nil, [:])
    }


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

            if let col = bestCol, bestDist < 0.15 {
                if let existing = assignments[col] {
                    assignments[col] = existing + " " + box.text
                } else {
                    assignments[col] = box.text
                }
            } else {
                if looksNumeric(box.text) {
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
                    assignments[.particulars] = (assignments[.particulars] ?? "") + " " + box.text
                }
            }
        }

        let particulars = assignments[.particulars]?.trimmingCharacters(in: .whitespaces) ?? ""
        let qty = assignments[.qty]?.trimmingCharacters(in: .whitespaces) ?? "1"

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

            let numericBoxes = sorted.filter { looksNumeric($0.text) }
            let textBoxes = sorted.filter { !looksNumeric($0.text) }

            var qty = "1"
            var name = ""
            var rate: String?
            var amount: String?

            if let firstNum = numericBoxes.first {
                let qtyCandidate = cleanPrice(firstNum.text)
                if let val = Double(qtyCandidate ?? ""), val < 500 {
                    qty = qtyCandidate ?? "1"
                }
            }

            if numericBoxes.count >= 3 {
                rate = cleanPrice(numericBoxes[numericBoxes.count - 2].text)
                amount = cleanPrice(numericBoxes.last!.text)
            } else if numericBoxes.count >= 2 {
                amount = cleanPrice(numericBoxes.last!.text)
            } else if numericBoxes.count == 1 && textBoxes.isEmpty {
                continue
            }

            name = textBoxes.map { $0.text }.joined(separator: " ")

            if name.isEmpty && sorted.count >= 2 {
                var textParts: [String] = []
                var numParts: [String] = []
                for box in sorted {
                    if looksNumeric(box.text) {
                        numParts.append(box.text)
                    } else {
                        textParts.append(box.text)
                    }
                }
                
                if !textParts.isEmpty {
                    name = textParts.joined(separator: " ")
                }
                
                if numParts.count >= 3 {
                    if let first = numParts.first, let val = Double(cleanPrice(first) ?? ""), val < 500 {
                        qty = cleanPrice(first) ?? "1"
                    }
                    rate = cleanPrice(numParts[numParts.count - 2])
                    amount = cleanPrice(numParts.last!)
                } else if numParts.count == 2 {
                    if let first = numParts.first, let val = Double(cleanPrice(first) ?? ""), val < 500 {
                        qty = cleanPrice(first) ?? "1"
                        amount = cleanPrice(numParts.last!)
                    } else {
                        rate = cleanPrice(numParts.first!)
                        amount = cleanPrice(numParts.last!)
                    }
                } else if numParts.count == 1 {
                    amount = cleanPrice(numParts.first!)
                }
            }

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
                        continue
                    }
                } else {
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

     func containsItemLikeContent(_ text: String) -> Bool {
        let hasNumbers = text.contains(where: { $0.isNumber })
        let hasLetters = text.contains(where: { $0.isLetter })
        return hasNumbers && hasLetters
    }


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

     func extractQtyAndUnit(_ qtyStr: String) -> (number: String, unit: String?) {
        var cleaned = convertHindiNumerals(qtyStr)
            .trimmingCharacters(in: .whitespaces)
        
        var foundUnit: String? = nil
        
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

     func cleanPrice(_ priceStr: String?) -> String? {
        guard var p = priceStr?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return nil }
        p = convertHindiNumerals(p)
        p = p.replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "Rs.", with: "")
            .replacingOccurrences(of: "Rs", with: "")
            .replacingOccurrences(of: "/-", with: "")
            .replacingOccurrences(of: ",", with: "")
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
