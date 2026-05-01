
import Vision
import UIKit

final class ProductFingerprintManager {

    private struct MatchCandidate {
        let item: Item
        let rawBestScore: Float
        let supportMeanScore: Float
        let calibratedScore: Float
        let strongMatchCount: Int
    }

    static let shared = ProductFingerprintManager()

    let clipThreshold: Float = 0.72
    let rawScoreFloor: Float = 0.78
    let minCalibratedMargin: Float = 0.04
    let minRawMargin: Float = 0.025
    let maxDetections = 5             
     let visionExtractor = VisionFeatureExtractor.shared
    private let embeddingPreprocessVersion = 2
    private let embeddingPreprocessVersionKey = "productEmbeddingPreprocessVersion"
    private let rebuildQueue = DispatchQueue(label: "com.tabs.embeddings.rebuild", qos: .utility)
    private var rebuildInProgress = false

     var cachedEmbeddings: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)]?
     var cacheTimestamp: TimeInterval = 0
     let cacheTTL: TimeInterval = 5

     func getStoredEmbeddings() -> [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)] {
        ensureEmbeddingsCurrent()
        guard UserDefaults.standard.integer(forKey: embeddingPreprocessVersionKey) >= embeddingPreprocessVersion else {
            return []
        }

        let now = CACurrentMediaTime()
        if let cached = cachedEmbeddings, now - cacheTimestamp < cacheTTL {
            return cached
        }
        let loaded = ProductEmbeddingStore.shared.loadAllEmbeddings()
        cachedEmbeddings = loaded
        cacheTimestamp = now
        return loaded
    }

    func invalidateEmbeddingCache() {
        cachedEmbeddings = nil
        cacheTimestamp = 0
    }

    func prepareEmbeddingsForCurrentExtractor() {
        ensureEmbeddingsCurrent()
    }

    private func ensureEmbeddingsCurrent() {
        let storedVersion = UserDefaults.standard.integer(forKey: embeddingPreprocessVersionKey)
        guard storedVersion < embeddingPreprocessVersion else { return }
        rebuildAllEmbeddingsForCurrentExtractor()
    }

    private func rebuildAllEmbeddingsForCurrentExtractor() {
        guard !rebuildInProgress else { return }
        rebuildInProgress = true
        invalidateEmbeddingCache()

        rebuildQueue.async { [weak self] in
            guard let self = self else { return }

            let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            let itemIDsToRefresh = allItems.compactMap { item -> UUID? in
                let photos = (try? AppDataModel.shared.dataModel.db.getProductPhotos(for: item.id)) ?? []
                return photos.isEmpty ? nil : item.id
            }

            guard !itemIDsToRefresh.isEmpty else {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(self.embeddingPreprocessVersion, forKey: self.embeddingPreprocessVersionKey)
                    self.rebuildInProgress = false
                }
                return
            }

            for itemID in itemIDsToRefresh {
                let semaphore = DispatchSemaphore(value: 0)
                self.updateEmbeddings(for: itemID) {
                    semaphore.signal()
                }
                semaphore.wait()
            }

            DispatchQueue.main.async {
                UserDefaults.standard.set(self.embeddingPreprocessVersion, forKey: self.embeddingPreprocessVersionKey)
                self.invalidateEmbeddingCache()
                self.rebuildInProgress = false
            }
        }
    }


    func matchObjects(in image: CGImage, completion: @escaping ([Item]) -> Void) {
        matchObjectsWithScores(in: image) { triples in
            completion(triples.map { $0.0 })
        }
    }

 
    func matchObjectsWithScores(in image: CGImage, completion: @escaping ([(Item, Float, Int)]) -> Void) {
        if let extractor = FeatureExtractorProvider.vectorExtractor {
            matchWithCLIP(image: image, extractor: extractor, completion: completion)
        } else {
            matchWithVision(image: image) { items in
                completion(items.map { ($0, 0.8, 1) })
            }
        }
    }

    func matchTracksWithScores(tracks: [[Float]], completion: @escaping ([(Item, Float, Int)]) -> Void) {
        let stored = getStoredEmbeddings()
        guard !stored.isEmpty else {
            completion([])
            return
        }
        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        let itemByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var results: [(Item, Float)] = []
        for embedding in tracks {
            let (item, score) = matchBestItem(vector: embedding, stored: stored, itemByID: itemByID)
            if let item = item { results.append((item, score)) }
        }
        let aggregated = Self.aggregateMatches(results)
        DispatchQueue.main.async { completion(aggregated) }
    }


     func matchWithCLIP(image: CGImage, extractor: FeatureVectorExtractor, completion: @escaping ([(Item, Float, Int)]) -> Void) {
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let stored = getStoredEmbeddings()

        guard !stored.isEmpty else {
            matchWithVision(image: image) { completion($0.map { ($0, 0.8, 1) }) }
            return
        }

        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        let itemByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemByBarcode = Dictionary(allItems.compactMap { item -> (String, Item)? in
            guard let code = item.barcode, !code.isEmpty else { return nil }
            return (code, item)
        }, uniquingKeysWith: { first, _ in first })

        func runMatch(detections: [(crop: CGImage, rect: CGRect)]) {
            DispatchQueue.global(qos: .userInitiated).async {
                var allMatches: [(Item, Float)] = []

                var barcodeMatched = Set<Int>()
                for (idx, (crop, _)) in detections.enumerated() {
                    if let barcode = self.detectBarcode(in: crop), let item = itemByBarcode[barcode] {
                        allMatches.append((item, 1.0))
                        barcodeMatched.insert(idx)
                    }
                }

                let clipCrops = detections.enumerated().compactMap { (idx, det) -> (Int, CGImage)? in
                    barcodeMatched.contains(idx) ? nil : (idx, det.crop)
                }
                guard !clipCrops.isEmpty else {
                    let aggregated = Self.aggregateMatches(allMatches)
                    DispatchQueue.main.async { completion(aggregated) }
                    return
                }

                let batchVectors = extractor.extractVectorBatch(from: clipCrops.map { $0.1 })

                let ocrGroup = DispatchGroup()
                var ocrResultsByIdx: [Int: ProductOCRResult] = [:]
                let ocrLock = NSLock()

                for (vecIdx, (_, crop)) in clipCrops.enumerated() {
                    ocrGroup.enter()
                    ProductOCRService.shared.extractFromProduct(image: crop) { result in
                        ocrLock.lock()
                        ocrResultsByIdx[vecIdx] = result
                        ocrLock.unlock()
                        ocrGroup.leave()
                    }
                }

                ocrGroup.wait()

                for (vecIdx, _) in clipCrops.enumerated() {
                    guard let vector = batchVectors[vecIdx] else { continue }

                    let rankedCandidates = self.rankCandidates(vector: vector, stored: stored, itemByID: itemByID, topK: 3)
                    guard let bestCandidate = rankedCandidates.first else { continue }

                    let ocrResult = ocrResultsByIdx[vecIdx]
                    var finalItem = bestCandidate.item
                    var finalScore = bestCandidate.calibratedScore
                    var usedOCREvidence = false

                    if rankedCandidates.count >= 2 {
                        let secondScore = rankedCandidates[1].calibratedScore
                        let scoreDiff = bestCandidate.calibratedScore - secondScore

                        if scoreDiff < 0.05, let ocr = ocrResult {
                            let ocrDisambiguated = self.disambiguateWithOCR(
                                candidates: rankedCandidates.map { ($0.item, $0.calibratedScore) },
                                ocrWeight: ocr.weight,
                                ocrMRP: ocr.mrp,
                                ocrProductName: ocr.productName
                            )
                            if let best = ocrDisambiguated {
                                finalItem = best.item
                                finalScore = min(best.score + 0.05, 1.0)
                                usedOCREvidence = best.item.id != bestCandidate.item.id || best.score > bestCandidate.calibratedScore + 0.01
                            }
                        }
                    }

                    if let ocr = ocrResult, ocr.weight != nil || ocr.mrp != nil {
                        if self.ocrMatchesItem(item: finalItem, ocrWeight: ocr.weight, ocrMRP: ocr.mrp) {
                            finalScore = min(finalScore + 0.03, 1.0)
                            usedOCREvidence = true
                        }
                    }

                    if self.isReliableMatch(
                        selectedItemID: finalItem.id,
                        finalScore: finalScore,
                        rankedCandidates: rankedCandidates,
                        usedOCREvidence: usedOCREvidence
                    ) {
                        allMatches.append((finalItem, finalScore))
                    }
                }

                let aggregated = Self.aggregateMatches(allMatches)
                DispatchQueue.main.async { completion(aggregated) }
            }
        }


        ObjectDetectionService.shared.detectObjects(in: image) { [weak self] visionBoxes in
            guard let self = self else { return }
            var finalCrops: [(CGImage, CGRect)] = visionBoxes.compactMap { box in
                guard let crop = self.makeFocusedCrop(from: image, box: box) else { return nil }
                return (crop, box.rect)
            }

            if finalCrops.isEmpty {
                let w = CGFloat(image.width)
                let h = CGFloat(image.height)
                let fallbackRect = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7)
                if let crop = image.cropping(to: fallbackRect) {
                    finalCrops = [(crop, fallbackRect)]
                }
            }

            runMatch(detections: finalCrops)
        }
    }


     func matchBestItem(vector: [Float], stored: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)], itemByID: [UUID: Item]) -> (Item?, Float) {
        let ranked = rankCandidates(vector: vector, stored: stored, itemByID: itemByID, topK: 2)
        guard let best = ranked.first else { return (nil, 0) }
        guard isReliableMatch(selectedItemID: best.item.id, finalScore: best.calibratedScore, rankedCandidates: ranked, usedOCREvidence: false) else {
            return (nil, best.calibratedScore)
        }
        return (best.item, best.calibratedScore)
    }

     func matchTopItems(vector: [Float], stored: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)], itemByID: [UUID: Item], topK: Int = 3) -> [(item: Item, score: Float)] {
        rankCandidates(vector: vector, stored: stored, itemByID: itemByID, topK: topK).map { ($0.item, $0.calibratedScore) }
    }

    private func rankCandidates(
        vector: [Float],
        stored: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)],
        itemByID: [UUID: Item],
        topK: Int
    ) -> [MatchCandidate] {
        var scoresByItem: [UUID: [Float]] = [:]
        for row in stored {
            let sim = ProductEmbeddingStore.cosineSimilarity(vector, row.embedding)
            guard sim.isFinite else { continue }
            scoresByItem[row.itemID, default: []].append(sim)
        }

        return scoresByItem.compactMap { itemID, scores in
            guard let item = itemByID[itemID], let rawBest = scores.max() else { return nil }
            let sortedScores = scores.sorted(by: >)
            let supportWindow = sortedScores.prefix(min(3, sortedScores.count))
            let supportMean = supportWindow.reduce(0, +) / Float(supportWindow.count)
            let strongMatchCount = scores.filter { $0 >= max(rawBest - 0.04, clipThreshold) }.count
            let supportBonus = min(0.03, Float(max(0, strongMatchCount - 1)) * 0.01)
            let calibratedScore = rawBest * 0.55 + supportMean * 0.45 + supportBonus

            guard rawBest >= clipThreshold * 0.9 || calibratedScore >= clipThreshold * 0.9 else { return nil }
            return MatchCandidate(
                item: item,
                rawBestScore: rawBest,
                supportMeanScore: supportMean,
                calibratedScore: calibratedScore,
                strongMatchCount: strongMatchCount
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.calibratedScore - rhs.calibratedScore) > 0.01 {
                return lhs.calibratedScore > rhs.calibratedScore
            }
            return lhs.rawBestScore > rhs.rawBestScore
        }
        .prefix(topK)
        .map { $0 }
    }

    private func isReliableMatch(
        selectedItemID: UUID,
        finalScore: Float,
        rankedCandidates: [MatchCandidate],
        usedOCREvidence: Bool
    ) -> Bool {
        guard let selected = rankedCandidates.first(where: { $0.item.id == selectedItemID }) else { return false }
        guard finalScore >= clipThreshold, selected.rawBestScore >= rawScoreFloor else { return false }

        guard let runnerUp = rankedCandidates.first(where: { $0.item.id != selectedItemID }) else {
            return true
        }

        let calibratedMargin = finalScore - runnerUp.calibratedScore
        let rawMargin = selected.rawBestScore - runnerUp.rawBestScore
        if usedOCREvidence {
            return calibratedMargin >= (minCalibratedMargin * 0.4) || rawMargin >= (minRawMargin * 0.4)
        }

        return calibratedMargin >= minCalibratedMargin || rawMargin >= minRawMargin
    }
    
     func disambiguateWithOCR(candidates: [(item: Item, score: Float)], ocrWeight: String?, ocrMRP: String?, ocrProductName: String?) -> (item: Item, score: Float)? {
        guard candidates.count >= 2 else { return candidates.first }
        
        let weightPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*(g|gm|kg|ml|l|ltr)"#, options: .caseInsensitive)
        var ocrWeightValue: Double?
        var ocrWeightUnit: String?
        
        if let w = ocrWeight, let regex = weightPattern {
            let match = regex.firstMatch(in: w, range: NSRange(w.startIndex..., in: w))
            if let vr = match.flatMap({ Range($0.range(at: 1), in: w) }),
               let ur = match.flatMap({ Range($0.range(at: 2), in: w) }),
               let val = Double(w[vr]) {
                ocrWeightValue = val
                ocrWeightUnit = String(w[ur]).lowercased()
            }
        }
        
        let ocrMRPValue = ocrMRP.flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
        
        var scored: [(item: Item, totalScore: Float)] = []
        
        for candidate in candidates {
            var ocrBonus: Float = 0
            let itemName = candidate.item.name.lowercased()
            
            if let ocrVal = ocrWeightValue, let ocrUnit = ocrWeightUnit, let regex = weightPattern {
                let nameMatches = regex.matches(in: itemName, range: NSRange(itemName.startIndex..., in: itemName))
                for nm in nameMatches {
                    if let vr = Range(nm.range(at: 1), in: itemName),
                       let ur = Range(nm.range(at: 2), in: itemName),
                       let itemVal = Double(itemName[vr]) {
                        let itemUnit = String(itemName[ur]).lowercased()
                        let ocrNorm = normalizeWeightToBase(value: ocrVal, unit: ocrUnit)
                        let itemNorm = normalizeWeightToBase(value: itemVal, unit: itemUnit)
                        if abs(ocrNorm - itemNorm) < 1.0 {
                            ocrBonus += 0.10
                            print("[ProductFinger] Weight match for \(candidate.item.name): OCR=\(ocrVal)\(ocrUnit) vs Item=\(itemVal)\(itemUnit)")
                        }
                    }
                }
            }
            
            if let mrp = ocrMRPValue {
                if abs(candidate.item.defaultSellingPrice - mrp) <= 2.0 {
                    ocrBonus += 0.05
                }
            }
            
            if let ocrName = ocrProductName?.lowercased() {
                let nameWords = itemName.split(separator: " ").map(String.init)
                let matchingWords = nameWords.filter { $0.count >= 3 && ocrName.contains($0) }
                if !matchingWords.isEmpty {
                    ocrBonus += Float(matchingWords.count) * 0.02
                }
            }
            
            scored.append((item: candidate.item, totalScore: candidate.score + ocrBonus))
        }
        
        let best = scored.max { $0.totalScore < $1.totalScore }
        guard let winner = best else { return candidates.first }
        
        let originalBest = candidates.first!
        if winner.item.id != originalBest.item.id {
            return (item: winner.item, score: winner.totalScore)
        }
        return (item: originalBest.item, score: originalBest.score)
    }
    
     func ocrMatchesItem(item: Item, ocrWeight: String?, ocrMRP: String?) -> Bool {
        let itemName = item.name.lowercased()
        
        if let w = ocrWeight {
            let weightPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*(g|gm|kg|ml|l)"#, options: .caseInsensitive)
            if let regex = weightPattern {
                let ocrMatch = regex.firstMatch(in: w, range: NSRange(w.startIndex..., in: w))
                let nameMatch = regex.firstMatch(in: itemName, range: NSRange(itemName.startIndex..., in: itemName))
                if let om = ocrMatch, let nm = nameMatch,
                   let ovr = Range(om.range(at: 1), in: w),
                   let nvr = Range(nm.range(at: 1), in: itemName),
                   let ocrVal = Double(w[ovr]),
                   let nameVal = Double(itemName[nvr]) {
                    let our = Range(om.range(at: 2), in: w).map { String(w[$0]).lowercased() } ?? ""
                    let nur = Range(nm.range(at: 2), in: itemName).map { String(itemName[$0]).lowercased() } ?? ""
                    let ocrNorm = normalizeWeightToBase(value: ocrVal, unit: our)
                    let nameNorm = normalizeWeightToBase(value: nameVal, unit: nur)
                    if abs(ocrNorm - nameNorm) < 1.0 { return true }
                }
            }
        }
        
        if let mrp = ocrMRP, let val = Double(mrp.filter { $0.isNumber || $0 == "." }) {
            if abs(item.defaultSellingPrice - val) <= 2.0 { return true }
        }
        
        return false
    }
    
     func normalizeWeightToBase(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "kg", "kgs": return value * 1000
        case "g", "gm", "gms", "gram", "grams": return value
        case "l", "ltr", "litre", "litres", "liter": return value * 1000
        case "ml": return value
        default: return value
        }
    }


     static func aggregateMatches(_ matches: [(Item, Float)]) -> [(Item, Float, Int)] {
        var bestByID: [UUID: (Item, Float, Int)] = [:]
        for (item, score) in matches {
            if let existing = bestByID[item.id] {
                bestByID[item.id] = (item, max(score, existing.1), existing.2 + 1)
            } else {
                bestByID[item.id] = (item, score, 1)
            }
        }
        return Array(bestByID.values)
    }


    static func dedupDetectionsByIoU(_ detections: [YOLODetection], iouThreshold: Float) -> [YOLODetection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [YOLODetection] = []
        for det in sorted {
            let dominated = kept.contains { existing in
                let inter = det.rect.intersection(existing.rect)
                guard !inter.isNull, inter.width > 0, inter.height > 0 else { return false }
                let interArea = inter.width * inter.height
                let unionArea = det.rect.width * det.rect.height + existing.rect.width * existing.rect.height - interArea
                return unionArea > 0 && Float(interArea / unionArea) > iouThreshold
            }
            if !dominated { kept.append(det) }
        }
        return kept
    }


     func detectBarcode(in image: CGImage) -> String? {
        detectBarcodeInImage(image)
    }

    func detectBarcodeInImage(_ image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return (request.results as? [VNBarcodeObservation])?.first?.payloadStringValue
    }


     func matchWithVision(image: CGImage, completion: @escaping ([Item]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            let photos = allItems.flatMap { item -> [(Item, Data)] in
                let pphotos = (try? AppDataModel.shared.dataModel.db.getProductPhotos(for: item.id)) ?? []
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dataDir = docs.appendingPathComponent("TabsData", isDirectory: true)
                return pphotos.compactMap { photo -> (Item, Data)? in
                    let path = dataDir.appendingPathComponent(photo.localPath)
                    guard let data = try? Data(contentsOf: path) else { return nil }
                    return (item, data)
                }
            }
            guard !photos.isEmpty else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            ObjectDetectionService.shared.detectObjects(in: image) { boxes in
                let queryPrints = boxes.compactMap { box -> VNFeaturePrintObservation? in
                    guard let crop = self.makeFocusedCrop(from: image, box: box) else { return nil }
                    return self.visionExtractor.extractFeaturePrint(from: crop)
                }
                guard !queryPrints.isEmpty else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let refGroup = DispatchGroup()
                let refLock = NSLock()
                var referencePrints: [(Item, VNFeaturePrintObservation)] = []

                for (item, imgData) in photos {
                    guard let cgImg = UIImage(data: imgData)?.cgImage else { continue }
                    refGroup.enter()
                    self.extractBestCrop(from: cgImg) { crop, _ in
                        defer { refGroup.leave() }
                        let targetImage = crop ?? cgImg
                        guard let refPrint = self.visionExtractor.extractFeaturePrint(from: targetImage) else { return }
                        refLock.lock()
                        referencePrints.append((item, refPrint))
                        refLock.unlock()
                    }
                }

                refGroup.notify(queue: .global(qos: .userInitiated)) {
                    var allMatches: [Item] = []
                    for q in queryPrints {
                        var bestMatch: Item?
                        var bestScore: Float = 0
                        for (item, refPrint) in referencePrints {
                            let sim = VisionFeatureExtractor.similarity(q, refPrint)
                            if sim >= 0.45 && sim > bestScore {
                                bestScore = sim
                                bestMatch = item
                            }
                        }
                        if let match = bestMatch {
                            allMatches.append(match)
                        }
                    }
                    DispatchQueue.main.async { completion(allMatches) }
                }
            }
        }
    }

     func cropImage(image: CGImage, to rect: CGRect) -> CGImage? {
        let x = max(0, Int(rect.origin.x))
        let y = max(0, Int(rect.origin.y))
        let w = min(image.width - x, max(1, Int(rect.width)))
        let h = min(image.height - y, max(1, Int(rect.height)))
        return image.cropping(to: CGRect(x: x, y: y, width: w, height: h))
    }


    func updateEmbeddings(for itemID: UUID, completion: (() -> Void)? = nil) {
        guard let extractor = FeatureExtractorProvider.vectorExtractor else {
            completion?()
            return
        }
        let photos = (try? AppDataModel.shared.dataModel.db.getProductPhotos(for: itemID)) ?? []
        guard photos.count >= 1 else {
            completion?()
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dataDir = docs.appendingPathComponent("TabsData", isDirectory: true)

        DispatchQueue.global(qos: .userInitiated).async {
            var vectors: [[Float]] = []
            let group = DispatchGroup()
            let lock = NSLock()

            for photo in photos {
                let path = dataDir.appendingPathComponent(photo.localPath)
                guard let data = try? Data(contentsOf: path),
                      let img = UIImage(data: data)?.cgImage else { continue }

                group.enter()
                self.extractBestCrop(from: img) { crop, _ in
                    let targetImage = crop ?? img
                    if let vec = extractor.extractVector(from: targetImage) {
                        lock.lock()
                        vectors.append(vec)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.wait()

            guard !vectors.isEmpty else {
                DispatchQueue.main.async { completion?() }
                return
            }

            ProductEmbeddingStore.shared.replaceEmbeddings(itemID: itemID, embeddings: vectors)
            self.invalidateEmbeddingCache()
            DispatchQueue.main.async { completion?() }
        }
    }

     func extractBestCrop(from image: CGImage, completion: @escaping (CGImage?, CGRect?) -> Void) {
        ObjectDetectionService.shared.detectObjects(in: image) { [weak self] boxes in
            guard let self = self else { return }
            
            if let best = boxes.max(by: {
                let aArea = $0.rect.width * $0.rect.height
                let bArea = $1.rect.width * $1.rect.height
                return aArea < bArea 
            }) {
                let crop = self.makeFocusedCrop(from: image, box: best)
                completion(crop, best.rect)
            } else {
                let w = CGFloat(image.width)
                let h = CGFloat(image.height)
                let centerRect = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7)
                let crop = image.cropping(to: centerRect)
                completion(crop, centerRect)
            }
        }
    }

    func removeEmbeddings(for itemID: UUID) {
        ProductEmbeddingStore.shared.deleteEmbedding(itemID: itemID)
    }

    private func makeFocusedCrop(from image: CGImage, box: DetectedObjectBox) -> CGImage? {
        if let masked = maskedCrop(from: image, box: box) {
            return masked
        }
        return cropImage(image: image, to: box.rect)
    }

    private func maskedCrop(from image: CGImage, box: DetectedObjectBox) -> CGImage? {
        guard let mask = box.mask else { return nil }

        let rect = box.rect.integral.standardized
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1,
              let crop = image.cropping(to: clamped) else { return nil }

        let width = crop.width
        let height = crop.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return crop }

        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scaleX = CGFloat(mask.width) / CGFloat(image.width)
        let scaleY = CGFloat(mask.height) / CGFloat(image.height)

        for y in 0..<height {
            for x in 0..<width {
                let globalX = clamped.minX + CGFloat(x)
                let globalY = clamped.minY + CGFloat(y)
                let mx = min(mask.width - 1, max(0, Int(globalX * scaleX)))
                let my = min(mask.height - 1, max(0, Int(globalY * scaleY)))
                let maskValue = mask.floats[my * mask.width + mx]
                if maskValue < 0.5 {
                    let idx = y * bytesPerRow + x * 4
                    pixels[idx] = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                }
            }
        }

        return context.makeImage() ?? crop
    }
}
