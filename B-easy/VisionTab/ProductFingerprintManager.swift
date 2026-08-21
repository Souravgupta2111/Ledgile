
import Vision
import UIKit

struct ProductScanOutcome {
    var matches: [(Item, Float, Int)]
    var overlays: [(rect: CGRect, label: String)]
    var ambiguous: [(Item, Item)]
    var allDetections: [(rect: CGRect, hasMask: Bool)]
}

final class ProductFingerprintManager {

    private struct MatchCandidate {
        let item: Item
        let rawBestScore: Float
        let supportMeanScore: Float
        let calibratedScore: Float
        let strongMatchCount: Int
    }

    static let shared = ProductFingerprintManager()

    let clipThreshold: Float = 0.84
    let rawScoreFloor: Float = 0.88
    let minCalibratedMargin: Float = 0.08
    let minRawMargin: Float = 0.06
    let maxLuminanceMismatch: Float = 0.18
    let maxSaturationMismatch: Float = 0.35
    /// When only one inventory item can match, demand near-duplicate confidence.
    let soleCandidateFloor: Float = 0.93
    let maxDetections = 12 
     let visionExtractor = VisionFeatureExtractor.shared
    private let embeddingPreprocessVersion = 3
    private let embeddingPreprocessVersionKey = "productEmbeddingPreprocessVersion"
    private let rebuildQueue = DispatchQueue(label: "com.tabs.embeddings.rebuild", qos: .utility)
    private var rebuildInProgress = false
    private(set) var isRebuildingEmbeddings = false

    static let embeddingsDidRebuildNotification = Notification.Name("ProductFingerprintManager.embeddingsDidRebuild")

     var cachedEmbeddings: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)]?
     var cachedColorProfiles: [UUID: ProductColorProfile]?
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
        cachedColorProfiles = nil
        cacheTimestamp = 0
    }

    private func getColorProfiles() -> [UUID: ProductColorProfile] {
        let now = CACurrentMediaTime()
        if let cached = cachedColorProfiles, now - cacheTimestamp < cacheTTL {
            return cached
        }
        var loaded = ProductEmbeddingStore.shared.loadAllColorProfiles()
        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        for item in allItems {
            guard loaded[item.id] == nil else { continue }
            let photos = (try? AppDataModel.shared.dataModel.db.getProductPhotos(for: item.id)) ?? []
            guard !photos.isEmpty,
                  let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { continue }
            let dataDir = docs.appendingPathComponent("TabsData", isDirectory: true)
            var samples: [ProductColorProfile] = []
            for photo in photos.prefix(6) {
                let path = dataDir.appendingPathComponent(photo.localPath)
                guard let data = try? Data(contentsOf: path),
                      let cg = UIImage(data: data)?.cgImage else { continue }
                samples.append(Self.computeColorProfile(from: cg))
            }
            guard !samples.isEmpty else { continue }
            let profile = Self.averageColorProfile(samples)
            loaded[item.id] = profile
            ProductEmbeddingStore.shared.saveColorProfile(itemID: item.id, profile: profile)
        }
        cachedColorProfiles = loaded
        return loaded
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
        isRebuildingEmbeddings = true
        invalidateEmbeddingCache()
        print("[ProductFinger] Rebuilding CLIP embeddings (preprocess v\(embeddingPreprocessVersion))…")

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
                    self.isRebuildingEmbeddings = false
                    NotificationCenter.default.post(name: Self.embeddingsDidRebuildNotification, object: nil)
                    print("[ProductFinger] No product photos to rebuild.")
                }
                return
            }

            for (idx, itemID) in itemIDsToRefresh.enumerated() {
                let semaphore = DispatchSemaphore(value: 0)
                self.updateEmbeddings(for: itemID) {
                    semaphore.signal()
                }
                semaphore.wait()
                print("[ProductFinger] Rebuilt \(idx + 1)/\(itemIDsToRefresh.count)")
            }

            DispatchQueue.main.async {
                UserDefaults.standard.set(self.embeddingPreprocessVersion, forKey: self.embeddingPreprocessVersionKey)
                self.invalidateEmbeddingCache()
                self.rebuildInProgress = false
                self.isRebuildingEmbeddings = false
                NotificationCenter.default.post(name: Self.embeddingsDidRebuildNotification, object: nil)
                print("[ProductFinger] ✅ Embedding rebuild complete for \(itemIDsToRefresh.count) items.")
            }
        }
    }


    func matchObjects(in image: CGImage, completion: @escaping ([Item]) -> Void) {
        matchObjectsWithOutcome(in: image) { outcome in
            completion(outcome.matches.map { $0.0 })
        }
    }

    func matchObjectsWithScores(in image: CGImage, completion: @escaping ([(Item, Float, Int)]) -> Void) {
        matchObjectsWithOutcome(in: image) { outcome in
            completion(outcome.matches)
        }
    }

    func matchObjectsWithOutcome(in image: CGImage, completion: @escaping (ProductScanOutcome) -> Void) {
        if let extractor = FeatureExtractorProvider.vectorExtractor {
            matchWithCLIP(image: image, extractor: extractor, completion: completion)
        } else {
            matchWithVision(image: image) { items in
                completion(ProductScanOutcome(matches: items.map { ($0, 0.8, 1) }, overlays: [], ambiguous: [], allDetections: []))
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


     func matchWithCLIP(image: CGImage, extractor: FeatureVectorExtractor, completion: @escaping (ProductScanOutcome) -> Void) {
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let stored = getStoredEmbeddings()
        let colorProfiles = getColorProfiles()

        guard !stored.isEmpty else {
            ObjectDetectionService.shared.detectObjects(in: image) { boxes in
                var enriched = boxes
                if MobileSAMService.isEnabled,
                   let sam = MobileSAMService.shared,
                   let encoding = sam.encodeImage(image) {
                    enriched = sam.generateMasks(encoding: encoding, boxes: boxes)
                }
                let detectionRects = enriched.map { (rect: $0.rect, hasMask: $0.mask != nil) }
                DispatchQueue.main.async {
                    completion(ProductScanOutcome(matches: [], overlays: [], ambiguous: [], allDetections: detectionRects))
                }
            }
            return
        }

        let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
        let itemByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemByBarcode = Dictionary(allItems.compactMap { item -> (String, Item)? in
            guard let code = item.barcode, !code.isEmpty else { return nil }
            return (code, item)
        }, uniquingKeysWith: { first, _ in first })

        func runMatch(detections: [(crop: CGImage, rect: CGRect)], allDetections: [(rect: CGRect, hasMask: Bool)]) {
            DispatchQueue.global(qos: .userInitiated).async {
                var allMatches: [(Item, Float)] = []
                var overlays: [(rect: CGRect, label: String)] = []
                var ambiguous: [(Item, Item)] = []

                var barcodeMatched = Set<Int>()
                for (idx, (crop, rect)) in detections.enumerated() {
                    if let barcode = self.detectBarcode(in: crop), let item = itemByBarcode[barcode] {
                        allMatches.append((item, 1.0))
                        overlays.append((rect, item.name))
                        barcodeMatched.insert(idx)
                    }
                }

                let clipCrops = detections.enumerated().compactMap { (idx, det) -> (Int, CGImage, CGRect)? in
                    barcodeMatched.contains(idx) ? nil : (idx, det.crop, det.rect)
                }
                guard !clipCrops.isEmpty else {
                    let aggregated = Self.aggregateMatches(allMatches)
                    DispatchQueue.main.async {
                        completion(ProductScanOutcome(matches: aggregated, overlays: overlays, ambiguous: ambiguous, allDetections: allDetections))
                    }
                    return
                }

                let batchVectors = extractor.extractVectorBatch(from: clipCrops.map { $0.1 })

                let ocrGroup = DispatchGroup()
                var ocrResultsByIdx: [Int: ProductOCRResult] = [:]
                let ocrLock = NSLock()

                for (vecIdx, (_, crop, _)) in clipCrops.enumerated() {
                    ocrGroup.enter()
                    ProductOCRService.shared.extractFromProduct(image: crop) { result in
                        ocrLock.lock()
                        ocrResultsByIdx[vecIdx] = result
                        ocrLock.unlock()
                        ocrGroup.leave()
                    }
                }

                ocrGroup.wait()

                for (vecIdx, (_, crop, rect)) in clipCrops.enumerated() {
                    guard let vector = batchVectors[vecIdx] else { continue }
                    let queryColor = Self.computeColorProfile(from: crop)

                    let rankedCandidates = self.rankCandidates(
                        vector: vector,
                        stored: stored,
                        itemByID: itemByID,
                        topK: 3,
                        queryColor: queryColor,
                        colorProfiles: colorProfiles
                    )
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
                        overlays.append((rect, finalItem.name))
                    } else if rankedCandidates.count >= 2,
                              rankedCandidates[0].calibratedScore >= self.clipThreshold,
                              rankedCandidates[1].calibratedScore >= self.clipThreshold * 0.95 {
                        let a = rankedCandidates[0].item
                        let b = rankedCandidates[1].item
                        ambiguous.append((a, b))
                        overlays.append((rect, "\(a.name) or \(b.name)?"))
                    }
                }

                let aggregated = Self.aggregateMatches(allMatches)
                DispatchQueue.main.async {
                    completion(ProductScanOutcome(matches: aggregated, overlays: overlays, ambiguous: ambiguous, allDetections: allDetections))
                }
            }
        }


        ObjectDetectionService.shared.detectObjects(in: image) { [weak self] visionBoxes in
            guard let self = self else { return }

            // ── SAM enrichment: attach pixel-perfect masks if enabled ──
            var enrichedBoxes = visionBoxes
            if MobileSAMService.isEnabled,
               let sam = MobileSAMService.shared,
               let encoding = sam.encodeImage(image) {
                enrichedBoxes = sam.generateMasks(encoding: encoding, boxes: visionBoxes)
            }

            // Track all raw detections for live visualization
            let detectionRects: [(rect: CGRect, hasMask: Bool)] = enrichedBoxes.map {
                (rect: $0.rect, hasMask: $0.mask != nil)
            }

            var finalCrops: [(CGImage, CGRect)] = enrichedBoxes.compactMap { box in
                guard let crop = self.makeFocusedCrop(from: image, box: box) else { return nil }
                return (crop, box.rect)
            }

            if finalCrops.isEmpty {
                DispatchQueue.main.async {
                    completion(ProductScanOutcome(matches: [], overlays: [], ambiguous: [], allDetections: detectionRects))
                }
                return
            }

            let capped = Array(finalCrops.prefix(self.maxDetections))
            runMatch(detections: capped, allDetections: detectionRects)
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

    /// CLIP a user-marked crop. Shopkeeper chose the box, but still require strong CLIP + color agreement.
    func matchMarkedCrop(_ crop: CGImage, completion: @escaping (Item?, Float) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let extractor = FeatureExtractorProvider.vectorExtractor,
                  let vector = extractor.extractVector(from: crop) else {
                DispatchQueue.main.async { completion(nil, 0) }
                return
            }
            let stored = self.getStoredEmbeddings()
            let colorProfiles = self.getColorProfiles()
            let queryColor = Self.computeColorProfile(from: crop)
            let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
            let itemByID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ranked = self.rankCandidates(
                vector: vector,
                stored: stored,
                itemByID: itemByID,
                topK: 2,
                queryColor: queryColor,
                colorProfiles: colorProfiles
            )
            guard let best = ranked.first else {
                DispatchQueue.main.async { completion(nil, 0) }
                return
            }
            let ok = self.isReliableMatch(
                selectedItemID: best.item.id,
                finalScore: best.calibratedScore,
                rankedCandidates: ranked,
                usedOCREvidence: false
            )
            DispatchQueue.main.async {
                completion(ok ? best.item : nil, best.calibratedScore)
            }
        }
    }

     func matchTopItems(vector: [Float], stored: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)], itemByID: [UUID: Item], topK: Int = 3) -> [(item: Item, score: Float)] {
        rankCandidates(vector: vector, stored: stored, itemByID: itemByID, topK: topK).map { ($0.item, $0.calibratedScore) }
    }

    private func rankCandidates(
        vector: [Float],
        stored: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)],
        itemByID: [UUID: Item],
        topK: Int,
        queryColor: ProductColorProfile? = nil,
        colorProfiles: [UUID: ProductColorProfile] = [:]
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

            // Reject one-off chance hits (single embedding high, others much lower).
            let supportGap = rawBest - supportMean
            if supportGap > 0.07 && strongMatchCount < 2 { return nil }

            guard rawBest >= rawScoreFloor * 0.97 || calibratedScore >= clipThreshold else { return nil }
            return MatchCandidate(
                item: item,
                rawBestScore: rawBest,
                supportMeanScore: supportMean,
                calibratedScore: calibratedScore,
                strongMatchCount: strongMatchCount
            )
        }
        .filter { candidate in
            guard let queryColor else { return true }
            return colorProfileCompatible(query: queryColor, itemID: candidate.item.id, profiles: colorProfiles)
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
            // Solo inventory match is the main false-positive trap (e.g. carpet → only charger).
            return finalScore >= soleCandidateFloor && selected.rawBestScore >= soleCandidateFloor
        }

        let calibratedMargin = finalScore - runnerUp.calibratedScore
        let rawMargin = selected.rawBestScore - runnerUp.rawBestScore
        if usedOCREvidence {
            return calibratedMargin >= (minCalibratedMargin * 0.5) && rawMargin >= (minRawMargin * 0.5)
        }

        return calibratedMargin >= minCalibratedMargin && rawMargin >= minRawMargin
    }

    struct ProductColorProfile {
        let luminance: Float
        let saturation: Float
    }

    static func computeColorProfile(from image: CGImage) -> ProductColorProfile {
        if let direct = computeColorProfileFromBitmap(image) { return direct }
        let w = max(1, min(image.width, 128))
        let h = max(1, min(image.height, 128))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ProductColorProfile(luminance: 0.5, saturation: 0)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return computeColorProfileFromPixels(pixels, width: w, height: h, bytesPerRow: w * 4)
    }

    private static func computeColorProfileFromBitmap(_ image: CGImage) -> ProductColorProfile? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0,
              let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = max(3, image.bitsPerPixel / 8)
        guard bpp >= 3 else { return nil }
        return computeColorProfileFromPixels(
            Array(UnsafeBufferPointer(start: ptr, count: CFDataGetLength(data))),
            width: w,
            height: h,
            bytesPerRow: image.bytesPerRow,
            bpp: bpp
        )
    }

    private static func computeColorProfileFromPixels(
        _ pixels: [UInt8],
        width w: Int,
        height h: Int,
        bytesPerRow: Int,
        bpp: Int = 4
    ) -> ProductColorProfile {
        let step = max(1, min(w, h) / 48)
        var lumSum: Float = 0
        var satSum: Float = 0
        var count: Float = 0

        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let i = y * bytesPerRow + x * bpp
                guard i + 2 < pixels.count else { continue }
                let r = Float(pixels[i]) / 255
                let g = Float(pixels[i + 1]) / 255
                let b = Float(pixels[i + 2]) / 255
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                lumSum += (maxC + minC) * 0.5
                satSum += maxC > 0.001 ? (maxC - minC) / maxC : 0
                count += 1
            }
        }
        guard count > 0 else { return ProductColorProfile(luminance: 0.5, saturation: 0) }
        return ProductColorProfile(luminance: lumSum / count, saturation: satSum / count)
    }

    private func colorProfileCompatible(query: ProductColorProfile, itemID: UUID, profiles: [UUID: ProductColorProfile]) -> Bool {
        guard let stored = profiles[itemID] else {
            // No training photos / color profile — only allow very strong CLIP elsewhere.
            return false
        }
        let lumDiff = abs(query.luminance - stored.luminance)
        if lumDiff > maxLuminanceMismatch { return false }
        if (query.luminance < 0.35 && stored.luminance > 0.65) || (query.luminance > 0.65 && stored.luminance < 0.35) {
            return false
        }
        // Carpet / colourful background vs pale product (or reverse).
        let satDiff = abs(query.saturation - stored.saturation)
        if satDiff > maxSaturationMismatch,
           max(query.saturation, stored.saturation) > 0.25 {
            return false
        }
        return true
    }

    private static func averageColorProfile(_ profiles: [ProductColorProfile]) -> ProductColorProfile {
        guard !profiles.isEmpty else { return ProductColorProfile(luminance: 0.5, saturation: 0) }
        let lum = profiles.map(\.luminance).reduce(0, +) / Float(profiles.count)
        let sat = profiles.map(\.saturation).reduce(0, +) / Float(profiles.count)
        return ProductColorProfile(luminance: lum, saturation: sat)
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
        
        guard let originalBest = candidates.first else { return nil }
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
                guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
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
                        guard let crop,
                              let refPrint = self.visionExtractor.extractFeaturePrint(from: crop) else { return }
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
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion?()
            return
        }
        let dataDir = docs.appendingPathComponent("TabsData", isDirectory: true)

        DispatchQueue.global(qos: .userInitiated).async {
            var vectors: [[Float]] = []
            var colorProfiles: [ProductColorProfile] = []
            let group = DispatchGroup()
            let lock = NSLock()

            for photo in photos {
                let path = dataDir.appendingPathComponent(photo.localPath)
                guard let data = try? Data(contentsOf: path),
                      let img = UIImage(data: data)?.cgImage else { continue }

                group.enter()
                self.extractBestCrop(from: img) { crop, _ in
                    guard let crop else {
                        group.leave()
                        return
                    }
                    if let vec = extractor.extractVector(from: crop) {
                        lock.lock()
                        vectors.append(vec)
                        colorProfiles.append(Self.computeColorProfile(from: crop))
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

            let meanProfile = Self.averageColorProfile(colorProfiles)
            ProductEmbeddingStore.shared.replaceEmbeddings(itemID: itemID, embeddings: vectors)
            ProductEmbeddingStore.shared.saveColorProfile(itemID: itemID, profile: meanProfile)
            self.invalidateEmbeddingCache()
            DispatchQueue.main.async { completion?() }
        }
    }

     func extractBestCrop(from image: CGImage, completion: @escaping (CGImage?, CGRect?) -> Void) {
        isolateProduct(in: image, tapInImage: nil, previousRect: nil) { crop, rect, _ in
            completion(crop, rect)
        }
    }

    /// Detect + optional SAM, then crop the chosen pack (not the table).
    func isolateProduct(
        in image: CGImage,
        tapInImage: CGPoint?,
        previousRect: CGRect?,
        completion: @escaping (_ crop: CGImage?, _ rect: CGRect?, _ detections: [(rect: CGRect, hasMask: Bool)]) -> Void
    ) {
        ObjectDetectionService.shared.detectObjects(in: image) { [weak self] boxes in
            guard let self else {
                completion(nil, nil, [])
                return
            }

            var enriched = boxes
            var encoding: SAMImageEncoding?
            if MobileSAMService.isEnabled, let sam = MobileSAMService.shared {
                encoding = sam.encodeImage(image)
                if let encoding {
                    enriched = sam.generateMasks(encoding: encoding, boxes: boxes)
                }
            }

            var chosen = self.pickIsolationBox(
                boxes: enriched,
                imageSize: CGSize(width: image.width, height: image.height),
                tapInImage: tapInImage,
                previousRect: previousRect
            )

            if chosen == nil, let tap = tapInImage {
                let side = min(CGFloat(image.width), CGFloat(image.height)) * 0.32
                let seed = CGRect(x: tap.x - side / 2, y: tap.y - side / 2, width: side, height: side)
                    .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                var box = DetectedObjectBox(rect: seed, confidence: 1, mask: nil)
                if let encoding, let sam = MobileSAMService.shared {
                    box = sam.generateMasks(encoding: encoding, boxes: [box]).first ?? box
                }
                chosen = box
            }

            let detections = enriched.map { (rect: $0.rect, hasMask: $0.mask != nil) }
            guard let chosen else {
                completion(nil, nil, detections)
                return
            }
            completion(self.makeFocusedCrop(from: image, box: chosen), chosen.rect, detections)
        }
    }

    private func pickIsolationBox(
        boxes: [DetectedObjectBox],
        imageSize: CGSize,
        tapInImage: CGPoint?,
        previousRect: CGRect?
    ) -> DetectedObjectBox? {
        guard !boxes.isEmpty else { return nil }
        if let tap = tapInImage {
            if let hit = boxes.first(where: { $0.rect.contains(tap) }) { return hit }
            return boxes.min(by: {
                hypot($0.rect.midX - tap.x, $0.rect.midY - tap.y) < hypot($1.rect.midX - tap.x, $1.rect.midY - tap.y)
            })
        }
        if let previous = previousRect {
            let ranked = boxes.map { box -> (DetectedObjectBox, CGFloat) in
                (box, ObjectDetectionService.shared.intersectionOverUnion(box.rect, previous))
            }
            if let best = ranked.max(by: { $0.1 < $1.1 }), best.1 >= 0.12 {
                return best.0
            }
        }
        return boxes.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })
    }

    func removeEmbeddings(for itemID: UUID) {
        ProductEmbeddingStore.shared.deleteEmbedding(itemID: itemID)
        ProductEmbeddingStore.shared.deleteColorProfile(itemID: itemID)
        invalidateEmbeddingCache()
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
