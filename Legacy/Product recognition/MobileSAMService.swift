import CoreML
import UIKit

// MARK: - MobileSAM Service (Plug-and-Play)
//
// Self-contained service that wraps the MobileSAM CoreML models.
// Delete this file + the MobileSAM-CoreML/ folder to fully remove SAM from the project.
//
// Model I/O:
//   Encoder:  image [1,3,1024,1024] → image_embeddings [1,256,64,64]
//   Decoder:  image_embeddings [1,256,64,64] + sparse_embeddings [1,N,256] (N=1...10)
//             + dense_embeddings [1,256,64,64] → masks [1,3,256,256] + iou_predictions [1,3]

struct SAMImageEncoding {
    let embedding: MLMultiArray
    let originalSize: CGSize
    let scale: CGFloat
    let resizedWidth: Int
    let resizedHeight: Int
}

final class MobileSAMService {

    private static let instanceLock = NSLock()
    private static var instance: MobileSAMService?

    /// Lazy load so Settings can check `modelsExistOnDisk` without compiling Core ML.
    static var shared: MobileSAMService? {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if instance == nil {
            instance = MobileSAMService()
        }
        return instance
    }

    private let embedDim = 256
    private let inputImageSize = 1024
    private let imageEmbeddingSize = 64
    private let maskOutputSize = 256

    private let encoderModel: MLModel
    private let decoderModel: MLModel

    private let gaussianMatrix: [[Float]]
    private let pointEmbeddings: [[Float]]
    private let noMaskEmbed: [Float]

    static let enabledKey = "vision.useMobileSAM"

    static var isEnabled: Bool {
        return false
    }

    private init?() {
        guard let encoderURL = Self.resolveCompiledModel(named: "mobile_sam_encoder"),
              let decoderURL = Self.resolveCompiledModel(named: "mobile_sam_decoder") else {
            print("[MobileSAM] ❌ Could not find encoder/decoder models")
            return nil
        }
        guard let weightsURL = Self.findPromptEncoderWeights() else {
            print("[MobileSAM] ❌ Could not find prompt_encoder_weights.json")
            return nil
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU

        do {
            self.encoderModel = try MLModel(contentsOf: encoderURL, configuration: config)
            self.decoderModel = try MLModel(contentsOf: decoderURL, configuration: config)
        } catch {
            print("[MobileSAM] ❌ Failed to load CoreML models: \(error)")
            return nil
        }

        do {
            let data = try Data(contentsOf: weightsURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let gm = json["gaussian_matrix"] as? [[Double]],
                  let pe = json["point_embeddings"] as? [[Double]],
                  let nap = json["not_a_point_embed"] as? [Double],
                  let nme = json["no_mask_embed"] as? [Double],
                  pe.count >= 4,
                  !nap.isEmpty else {
                print("[MobileSAM] ❌ Invalid prompt encoder weights format")
                return nil
            }
            self.gaussianMatrix = gm.map { $0.map { Float($0) } }
            self.pointEmbeddings = pe.map { $0.map { Float($0) } }
            self.noMaskEmbed = nme.map { Float($0) }
        } catch {
            print("[MobileSAM] ❌ Failed to load prompt encoder weights: \(error)")
            return nil
        }

        print("[MobileSAM] ✅ Service initialized (encoder + decoder + prompt weights)")
    }

    // MARK: - Public API

    /// Encode the full image once per frame. Call off the main thread.
    func encodeImage(_ image: CGImage) -> SAMImageEncoding? {
        let start = CFAbsoluteTimeGetCurrent()
        let originalSize = CGSize(width: image.width, height: image.height)
        let letterbox = letterboxGeometry(for: originalSize)

        guard let inputArray = preprocessImage(image, letterbox: letterbox) else {
            print("[MobileSAM] ❌ Image preprocessing failed")
            return nil
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["image": MLFeatureValue(multiArray: inputArray)]
            )
            let output = try encoderModel.prediction(from: inputFeatures)
            guard let embedding = output.featureValue(for: "image_embeddings")?.multiArrayValue else {
                print("[MobileSAM] ❌ Encoder output missing image_embeddings")
                return nil
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("[MobileSAM] Encoder took \(String(format: "%.1f", elapsed * 1000))ms")
            return SAMImageEncoding(
                embedding: embedding,
                originalSize: originalSize,
                scale: letterbox.scale,
                resizedWidth: letterbox.resizedWidth,
                resizedHeight: letterbox.resizedHeight
            )
        } catch {
            print("[MobileSAM] ❌ Encoder prediction failed: \(error)")
            return nil
        }
    }

    /// Generate masks for each box using the cached image embedding.
    func generateMasks(
        encoding: SAMImageEncoding,
        boxes: [DetectedObjectBox]
    ) -> [DetectedObjectBox] {
        let start = CFAbsoluteTimeGetCurrent()
        let denseEmbedding = makeDenseEmbedding()

        var enrichedBoxes: [DetectedObjectBox] = []
        for box in boxes {
            if let denseEmbedding,
               let enriched = generateMaskForBox(
                encoding: encoding,
                box: box,
                denseEmbedding: denseEmbedding
               ) {
                enrichedBoxes.append(enriched)
            } else {
                enrichedBoxes.append(box)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("[MobileSAM] Masks for \(boxes.count) boxes took \(String(format: "%.1f", elapsed * 1000))ms")
        return enrichedBoxes
    }

    // MARK: - Letterbox

    private struct Letterbox {
        let scale: CGFloat
        let resizedWidth: Int
        let resizedHeight: Int
    }

    private func letterboxGeometry(for original: CGSize) -> Letterbox {
        let longSide = max(original.width, original.height)
        let scale = CGFloat(inputImageSize) / longSide
        var newW = Int((original.width * scale).rounded())
        var newH = Int((original.height * scale).rounded())
        newW = min(inputImageSize, max(1, newW))
        newH = min(inputImageSize, max(1, newH))
        return Letterbox(scale: scale, resizedWidth: newW, resizedHeight: newH)
    }

    /// Longest-side resize, pad bottom/right with 0 in *normalized* space (SAM preprocess order).
    private func preprocessImage(_ image: CGImage, letterbox: Letterbox) -> MLMultiArray? {
        let size = inputImageSize
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]

        let rw = letterbox.resizedWidth
        let rh = letterbox.resizedHeight
        var resizedPixels = [UInt8](repeating: 0, count: rw * rh * 4)
        let resizedBytes = rw * 4
        guard let resizedContext = CGContext(
            data: &resizedPixels,
            width: rw,
            height: rh,
            bitsPerComponent: 8,
            bytesPerRow: resizedBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        resizedContext.translateBy(x: 0, y: CGFloat(rh))
        resizedContext.scaleBy(x: 1, y: -1)
        resizedContext.interpolationQuality = .high
        resizedContext.draw(image, in: CGRect(x: 0, y: 0, width: rw, height: rh))

        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
            dataType: .float16
        ) else { return nil }

        let totalPixels = size * size
        let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: 3 * totalPixels)
        for i in 0..<(3 * totalPixels) { ptr[i] = 0 }

        for y in 0..<rh {
            let srcRow = (rh - 1 - y) * rw
            for x in 0..<rw {
                let pi = (srcRow + x) * 4
                let dest = y * size + x
                let r = Float(resizedPixels[pi]) / 255.0
                let g = Float(resizedPixels[pi + 1]) / 255.0
                let b = Float(resizedPixels[pi + 2]) / 255.0
                ptr[dest] = Float16((r - mean[0]) / std[0])
                ptr[totalPixels + dest] = Float16((g - mean[1]) / std[1])
                ptr[2 * totalPixels + dest] = Float16((b - mean[2]) / std[2])
            }
        }

        return array
    }

    // MARK: - Per-Box Mask Generation

    private func generateMaskForBox(
        encoding: SAMImageEncoding,
        box: DetectedObjectBox,
        denseEmbedding: MLMultiArray
    ) -> DetectedObjectBox? {
        let scale = encoding.scale
        let x1 = Float(box.rect.minX * scale)
        let y1 = Float(box.rect.minY * scale)
        let x2 = Float(box.rect.maxX * scale)
        let y2 = Float(box.rect.maxY * scale)

        guard let sparseArray = encodeBoxPrompt(x1: x1, y1: y1, x2: x2, y2: y2) else {
            return nil
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
                "image_embeddings": MLFeatureValue(multiArray: encoding.embedding),
                "sparse_embeddings": MLFeatureValue(multiArray: sparseArray),
                "dense_embeddings": MLFeatureValue(multiArray: denseEmbedding)
            ])
            let output = try decoderModel.prediction(from: inputFeatures)

            guard let masksArray = output.featureValue(for: "masks")?.multiArrayValue,
                  let iouArray = output.featureValue(for: "iou_predictions")?.multiArrayValue else {
                return nil
            }

            let bestMaskIndex = selectBestMask(iouPredictions: iouArray)
            let mask = extractMask(
                from: masksArray,
                index: bestMaskIndex,
                encoding: encoding
            )

            return DetectedObjectBox(
                rect: box.rect,
                confidence: box.confidence,
                mask: mask
            )
        } catch {
            print("[MobileSAM] ❌ Decoder prediction failed: \(error)")
            return nil
        }
    }

    // MARK: - Prompt Encoder

    /// Two SAM box tokens: top-left (type 2) and bottom-right (type 3). Shape [1, 2, 256].
    private func encodeBoxPrompt(x1: Float, y1: Float, x2: Float, y2: Float) -> MLMultiArray? {
        let posEnc1 = positionalEncoding(x: x1 + 0.5, y: y1 + 0.5)
        let posEnc2 = positionalEncoding(x: x2 + 0.5, y: y2 + 0.5)
        guard posEnc1.count == embedDim, posEnc2.count == embedDim,
              pointEmbeddings.count >= 4 else { return nil }

        let cornerEmbed1 = pointEmbeddings[2]
        let cornerEmbed2 = pointEmbeddings[3]

        var token0 = [Float](repeating: 0, count: embedDim)
        var token1 = [Float](repeating: 0, count: embedDim)
        for i in 0..<embedDim {
            token0[i] = posEnc1[i] + cornerEmbed1[i]
            token1[i] = posEnc2[i] + cornerEmbed2[i]
        }

        guard let array = try? MLMultiArray(
            shape: [1, 2, NSNumber(value: embedDim)],
            dataType: .float16
        ) else { return nil }

        let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: 2 * embedDim)
        for i in 0..<embedDim {
            ptr[i] = Float16(token0[i])
            ptr[embedDim + i] = Float16(token1[i])
        }
        return array
    }

    /// Fourier PE: [0,1] → [-1,1] → gaussian → 2π → sin/cos.
    private func positionalEncoding(x: Float, y: Float) -> [Float] {
        var nx = x / Float(inputImageSize)
        var ny = y / Float(inputImageSize)
        nx = 2 * nx - 1
        ny = 2 * ny - 1

        let numFreqs = gaussianMatrix[0].count
        var projection = [Float](repeating: 0, count: numFreqs)
        let twoPi = Float.pi * 2
        for j in 0..<numFreqs {
            projection[j] = (nx * gaussianMatrix[0][j] + ny * gaussianMatrix[1][j]) * twoPi
        }

        var encoding = [Float](repeating: 0, count: embedDim)
        for j in 0..<numFreqs {
            encoding[j] = sin(projection[j])
            encoding[numFreqs + j] = cos(projection[j])
        }
        return encoding
    }

    private func makeDenseEmbedding() -> MLMultiArray? {
        let spatial = imageEmbeddingSize * imageEmbeddingSize
        guard let array = try? MLMultiArray(
            shape: [1, NSNumber(value: embedDim), NSNumber(value: imageEmbeddingSize), NSNumber(value: imageEmbeddingSize)],
            dataType: .float16
        ) else { return nil }

        let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: embedDim * spatial)
        for c in 0..<embedDim {
            let val = Float16(noMaskEmbed[c])
            let channelOffset = c * spatial
            for s in 0..<spatial {
                ptr[channelOffset + s] = val
            }
        }
        return array
    }

    // MARK: - Mask Post-Processing

    private func selectBestMask(iouPredictions: MLMultiArray) -> Int {
        let count = min(3, iouPredictions.count)
        let ptr = iouPredictions.dataPointer.bindMemory(to: Float16.self, capacity: count)
        var bestIdx = 0
        var bestVal = Float(ptr[0])
        for i in 1..<count {
            let val = Float(ptr[i])
            if val > bestVal {
                bestVal = val
                bestIdx = i
            }
        }
        return bestIdx
    }

    /// Upsample logits to 1024, crop letterbox pad, upsample to original size, then threshold.
    private func extractMask(
        from masksArray: MLMultiArray,
        index: Int,
        encoding: SAMImageEncoding
    ) -> (width: Int, height: Int, floats: [Float]) {
        let maskW = maskOutputSize
        let maskH = maskOutputSize
        let maskPixels = maskW * maskH
        let ptr = masksArray.dataPointer.bindMemory(to: Float16.self, capacity: 3 * maskPixels)

        let offset = index * maskPixels
        var logits = [Float](repeating: 0, count: maskPixels)
        for i in 0..<maskPixels {
            logits[i] = Float(ptr[offset + i])
        }

        let canvas = resizeBilinear(logits, srcW: maskW, srcH: maskH, dstW: inputImageSize, dstH: inputImageSize)

        let rw = encoding.resizedWidth
        let rh = encoding.resizedHeight
        var cropped = [Float](repeating: 0, count: rw * rh)
        for y in 0..<rh {
            let srcRow = y * inputImageSize
            let dstRow = y * rw
            for x in 0..<rw {
                cropped[dstRow + x] = canvas[srcRow + x]
            }
        }

        let outW = max(1, Int(encoding.originalSize.width.rounded()))
        let outH = max(1, Int(encoding.originalSize.height.rounded()))
        let resized = resizeBilinear(cropped, srcW: rw, srcH: rh, dstW: outW, dstH: outH)
        let binary = resized.map { $0 > 0 ? Float(1) : Float(0) }
        return (width: outW, height: outH, floats: binary)
    }

    private func resizeBilinear(_ src: [Float], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Float] {
        if srcW == dstW && srcH == dstH { return src }
        var dst = [Float](repeating: 0, count: dstW * dstH)
        let scaleX = Float(srcW) / Float(dstW)
        let scaleY = Float(srcH) / Float(dstH)
        for y in 0..<dstH {
            let srcY = (Float(y) + 0.5) * scaleY - 0.5
            let y0 = max(0, min(srcH - 1, Int(floor(srcY))))
            let y1 = max(0, min(srcH - 1, y0 + 1))
            let wy = srcY - Float(y0)
            for x in 0..<dstW {
                let srcX = (Float(x) + 0.5) * scaleX - 0.5
                let x0 = max(0, min(srcW - 1, Int(floor(srcX))))
                let x1 = max(0, min(srcW - 1, x0 + 1))
                let wx = srcX - Float(x0)
                let v00 = src[y0 * srcW + x0]
                let v10 = src[y0 * srcW + x1]
                let v01 = src[y1 * srcW + x0]
                let v11 = src[y1 * srcW + x1]
                let top = v00 + (v10 - v00) * wx
                let bot = v01 + (v11 - v01) * wx
                dst[y * dstW + x] = top + (bot - top) * wy
            }
        }
        return dst
    }

    // MARK: - File Discovery

    private static func resolveCompiledModel(named name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return bundled
        }
        if let bundled = Bundle.main.url(forResource: name, withExtension: "mlmodelc", subdirectory: "MobileSAM-CoreML") {
            return bundled
        }
        if let package = findModelPackage(named: name) {
            return compileIfNeeded(at: package)
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(name).mlmodelc")
        if let cache, FileManager.default.fileExists(atPath: cache.path) {
            return cache
        }
        return nil
    }

    private static func findModelPackage(named name: String) -> URL? {
        let fileName = "\(name).mlpackage"
        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("MobileSAM-CoreML/\(fileName)"),
            Bundle.main.bundleURL.appendingPathComponent(fileName),
        ]
        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage", subdirectory: "MobileSAM-CoreML") {
            candidates.insert(url, at: 0)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            candidates.insert(url, at: 0)
        }
        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)
            candidates.append(resourceURL.appendingPathComponent("MobileSAM-CoreML/\(fileName)"))
            candidates.append(resourceURL.appendingPathComponent(fileName))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private static func compileIfNeeded(at packageURL: URL) -> URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelName = packageURL.deletingPathExtension().lastPathComponent
        let compiledURL = cacheDir.appendingPathComponent("\(modelName).mlmodelc")

        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }

        do {
            let tempCompiled = try MLModel.compileModel(at: packageURL)
            if FileManager.default.fileExists(atPath: compiledURL.path) {
                try FileManager.default.removeItem(at: compiledURL)
            }
            try FileManager.default.copyItem(at: tempCompiled, to: compiledURL)
            print("[MobileSAM] ✅ Compiled \(modelName) to cache")
            return compiledURL
        } catch {
            print("[MobileSAM] ❌ Failed to compile \(modelName): \(error)")
            return nil
        }
    }

    private static func findPromptEncoderWeights() -> URL? {
        if let bundled = Bundle.main.url(forResource: "mobile_sam_prompt_encoder_weights", withExtension: "json") {
            return bundled
        }
        if let bundled = Bundle.main.url(
            forResource: "mobile_sam_prompt_encoder_weights",
            withExtension: "json",
            subdirectory: "MobileSAM-CoreML"
        ) {
            return bundled
        }

        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("MobileSAM-CoreML/mobile_sam_prompt_encoder_weights.json"),
            Bundle.main.bundleURL.appendingPathComponent("mobile_sam_prompt_encoder_weights.json"),
        ]
        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)
            candidates.append(resourceURL.appendingPathComponent("MobileSAM-CoreML/mobile_sam_prompt_encoder_weights.json"))
            candidates.append(resourceURL.appendingPathComponent("mobile_sam_prompt_encoder_weights.json"))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    /// Used by Settings to show/hide the toggle without loading Core ML.
    static var modelsExistOnDisk: Bool {
        if Bundle.main.url(forResource: "mobile_sam_encoder", withExtension: "mlmodelc") != nil,
           Bundle.main.url(forResource: "mobile_sam_decoder", withExtension: "mlmodelc") != nil {
            return true
        }
        if Bundle.main.url(forResource: "mobile_sam_encoder", withExtension: "mlmodelc", subdirectory: "MobileSAM-CoreML") != nil,
           Bundle.main.url(forResource: "mobile_sam_decoder", withExtension: "mlmodelc", subdirectory: "MobileSAM-CoreML") != nil {
            return true
        }
        return findModelPackage(named: "mobile_sam_encoder") != nil
            && findModelPackage(named: "mobile_sam_decoder") != nil
            && findPromptEncoderWeights() != nil
    }
}
