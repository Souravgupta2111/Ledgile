//  Vision OCR on product packaging: brand, product name, weight, MRP (English + Hindi).

import Vision
import UIKit

struct ProductOCRResult {
    var brand: String?
    var productName: String?
    var weight: String?
    var mrp: String?         
    var rawLines: [String]
}

final class ProductOCRService {
    static let shared = ProductOCRService()
     init() {}

    func extractFromProduct(image: CGImage, completion: @escaping (ProductOCRResult) -> Void) {
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let result = self?.parseProductOCR(lines: lines) ?? ProductOCRResult(brand: nil, productName: nil, weight: nil, mrp: nil, rawLines: lines)
            completion(result)
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "hi"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

     func parseProductOCR(lines: [String]) -> ProductOCRResult {
        var brand: String?
        var productName: String?
        var weight: String?
        var mrp: String?
        let weightPattern = try? NSRegularExpression(pattern: #"\d+\s*(g|kg|ml|L|litre|litres|G|ML)"#, options: .caseInsensitive)
        let mrpPattern = try? NSRegularExpression(pattern: #"(?:MRP|Rs?\.?|₹)\s*:?\s*(\d+(?:\.\d+)?)"#, options: .caseInsensitive)
        let rupeePattern = try? NSRegularExpression(pattern: #"₹\s*(\d+(?:\.\d+)?)"#, options: .caseInsensitive)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if weight == nil, let w = weightPattern?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)).map({ String(t[Range($0.range, in: t)!]) }) {
                weight = w
            }
            if mrp == nil {
                if let m = mrpPattern?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)).flatMap({ Range($0.range(at: 1), in: t).map { String(t[$0]) } }) {
                    mrp = m
                } else if let m = rupeePattern?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)).flatMap({ Range($0.range(at: 1), in: t).map { String(t[$0]) } }) {
                    mrp = m
                }
            }
            if brand == nil, t.count > 1, t.count < 25, !t.contains("MRP"), !t.contains("₹"), weightPattern?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) == nil {
                if productName == nil { productName = t }
                else if brand == nil { brand = productName; productName = t }
            }
        }
        if productName == nil, let first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty {
            productName = first
        }
        return ProductOCRResult(brand: brand, productName: productName, weight: weight, mrp: mrp, rawLines: lines)
    }
}
