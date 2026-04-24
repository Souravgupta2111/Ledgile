//  Extract feature vector from image (crop) for matching.
//  CLIP (CoreML) preferred; else TFLite MobileNetV3; else Vision feature print.

import UIKit
import CoreImage
import Vision
import CoreML
import Accelerate


protocol FeatureVectorExtractor {
    var dimension: Int { get }
    func extractVector(from image: CGImage) -> [Float]?
    
    func extractVectorBatch(from images: [CGImage]) -> [[Float]?]
}

extension FeatureVectorExtractor {
    func extractVectorBatch(from images: [CGImage]) -> [[Float]?] {
        return images.map { extractVector(from: $0) }
    }
}

#if canImport(TensorFlowLite)
import TensorFlowLite
#endif

// MARK: - Vision fallback (no vector; ProductFingerprintManager uses photo-by-photo comparison when this is the only path)


final class VisionFeatureExtractor {
    static let shared = VisionFeatureExtractor()
     init() {}

    func extractFeaturePrint(from image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    static func similarity(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        var dist: Float = 999
        try? a.computeDistance(&dist, to: b)
        return 1 / (1 + dist)
    }
}

// MARK: - CLIP CoreML (512-dim, preferred for inventory/sales matching)

final class CLIPFeatureExtractor: FeatureVectorExtractor {
    static let shared = CLIPFeatureExtractor()
     var model: MLModel?
     var inputSize = 256
     let queue = DispatchQueue(label: "com.tabs.clip", qos: .userInitiated)
     let ciContext = CIContext()
   
     var inputIsMultiArray = false
     var inputName = "image"

    var dimension: Int { 512 }
    var isAvailable: Bool { model != nil }

     init() {
        loadModel()
    }

     func loadModel() {
        let mobileclipNames = ["mobileclip_s2_image_fp16", "mobileclip_s2_image", "mobileclip_s2"]
        for name in mobileclipNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                loadModel(at: url, name: name, size: 256)
                return
            }
        }
        let clipNames = ["CLIPImageEncoder", "CLIP_ViT_B32"]
        for name in clipNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                loadModel(at: url, name: name, size: 224)
                return
            }
        }
    }

     func loadModel(at url: URL, name: String = "", size: Int = 256) {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let loaded = try MLModel(contentsOf: url, configuration: config)
            model = loaded
            inputSize = size

      
            let inputs = loaded.modelDescription.inputDescriptionsByName
            for (key, desc) in inputs {
                inputName = key
                if desc.type == .multiArray {
                    inputIsMultiArray = true
                    if let mac = desc.multiArrayConstraint {
                    }
                } else if desc.type == .image {
                    inputIsMultiArray = false
                    if let ic = desc.imageConstraint {
                    }
                }
            }

        } catch {
        }
    }

    // MARK: - Global mean embedding for centering
   
     static let globalMean: [Float] = {
        guard let url = Bundle.main.url(forResource: "clip_mean_embedding", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            Array(UnsafeBufferPointer(start: ptr.bindMemory(to: Float.self).baseAddress!, count: count))
        }
    }()

   
    static func postProcess(_ vec: inout [Float]) {
        // Dataset-level mean-centering dramatically improves separation for grocery items.
        // This uses the precomputed corpus mean bundled with the app, then L2-normalizes.
        if globalMean.count == vec.count {
            vDSP_vsub(globalMean, 1, vec, 1, &vec, 1, vDSP_Length(vec.count))
        }
        var sumSq: Float = 0
        vDSP_dotpr(vec, 1, vec, 1, &sumSq, vDSP_Length(vec.count))
        var norm = sqrtf(sumSq)
        if norm > 1e-8 {
            vDSP_vsdiv(vec, 1, &norm, &vec, 1, vDSP_Length(vec.count))
        }
    }

    func extractVector(from image: CGImage) -> [Float]? {
        guard let model = model else { return nil }
        return queue.sync {
            var raw: [Float]?
            if inputIsMultiArray {
                raw = extractViaMultiArray(model: model, image: image)
            } else {
                raw = extractViaPixelBuffer(model: model, image: image)
            }
            guard var vec = raw, !vec.isEmpty else { return nil }
            Self.postProcess(&vec)
            return vec
        }
    }

    // MARK: - Batch Extraction (potato-sorter speed)
    // Process all crops in ONE CoreML batch prediction call.
    

    func extractVectorBatch(from images: [CGImage]) -> [[Float]?] {
        guard let model = model, !images.isEmpty else { return images.map { _ in nil } }
        return queue.sync {
            let batchStart = CFAbsoluteTimeGetCurrent()

            if inputIsMultiArray {
                return batchViaMultiArray(model: model, images: images, startTime: batchStart)
            } else {
                return batchViaPixelBuffer(model: model, images: images, startTime: batchStart)
            }
        }
    }

     func batchViaMultiArray(model: MLModel, images: [CGImage], startTime: Double) -> [[Float]?] {
        let desc = model.modelDescription.inputDescriptionsByName[inputName]
        let shape: [Int]
        if let mac = desc?.multiArrayConstraint {
            shape = mac.shape.map { $0.intValue }
        } else {
            shape = [1, 3, inputSize, inputSize]
        }
        let isNCHW = shape.count == 4 && shape[1] == 3

        let prepStart = CFAbsoluteTimeGetCurrent()
        var providers = [MLFeatureProvider?](repeating: nil, count: images.count)
        let prepGroup = DispatchGroup()
        let prepQueue = DispatchQueue(label: "clip.prep", attributes: .concurrent)

        for (idx, img) in images.enumerated() {
            prepGroup.enter()
            prepQueue.async {
                defer { prepGroup.leave() }
                guard let resized = self.resizeToInput(cgImage: img, width: self.inputSize, height: self.inputSize),
                      let multiArray = self.imageToMultiArray(cgImage: resized, shape: shape, nchw: isNCHW),
                      let provider = try? MLDictionaryFeatureProvider(dictionary: [self.inputName: MLFeatureValue(multiArray: multiArray)]) else {
                    return
                }
                providers[idx] = provider
            }
        }
        prepGroup.wait()
        let prepMs = (CFAbsoluteTimeGetCurrent() - prepStart) * 1000
        let validProviders = providers.compactMap { $0 }

        let inferStart = CFAbsoluteTimeGetCurrent()
        let batchProvider = MLArrayBatchProvider(array: validProviders)
        guard let batchOutput = try? model.predictions(fromBatch: batchProvider) else {
            return images.map { extractVector(from: $0) }
        }
        let inferMs = (CFAbsoluteTimeGetCurrent() - inferStart) * 1000

        var results = [[Float]?](repeating: nil, count: images.count)
        var batchIdx = 0
        for (origIdx, provider) in providers.enumerated() {
            guard provider != nil, batchIdx < batchOutput.count else { continue }
            let output = batchOutput.features(at: batchIdx)
            batchIdx += 1
            for name in output.featureNames {
                guard let feat = output.featureValue(for: name),
                      var vec = feat.multiArrayValue?.toFloatArray(), !vec.isEmpty else { continue }
                Self.postProcess(&vec)
                results[origIdx] = vec
                break
            }
        }
        let totalMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return results
    }

     func batchViaPixelBuffer(model: MLModel, images: [CGImage], startTime: Double) -> [[Float]?] {
        // Parallel preprocessing
        let prepStart = CFAbsoluteTimeGetCurrent()
        var providers = [MLFeatureProvider?](repeating: nil, count: images.count)
        let prepGroup = DispatchGroup()
        let prepQueue = DispatchQueue(label: "clip.prep.px", attributes: .concurrent)

        for (idx, img) in images.enumerated() {
            prepGroup.enter()
            prepQueue.async {
                defer { prepGroup.leave() }
                guard let resized = self.resizeToInput(cgImage: img, width: self.inputSize, height: self.inputSize),
                      let buffer = self.pixelBuffer(from: resized),
                      let provider = try? MLDictionaryFeatureProvider(dictionary: [self.inputName: MLFeatureValue(pixelBuffer: buffer)]) else {
                    return
                }
                providers[idx] = provider
            }
        }
        prepGroup.wait()
        let prepMs = (CFAbsoluteTimeGetCurrent() - prepStart) * 1000

        let validProviders = providers.compactMap { $0 }
        let inferStart = CFAbsoluteTimeGetCurrent()
        let batchProvider = MLArrayBatchProvider(array: validProviders)
        guard let batchOutput = try? model.predictions(fromBatch: batchProvider) else {
            return images.map { extractVector(from: $0) }
        }
        let inferMs = (CFAbsoluteTimeGetCurrent() - inferStart) * 1000

        var results = [[Float]?](repeating: nil, count: images.count)
        var batchIdx = 0
        for (origIdx, provider) in providers.enumerated() {
            guard provider != nil, batchIdx < batchOutput.count else { continue }
            let output = batchOutput.features(at: batchIdx)
            batchIdx += 1
            for name in output.featureNames {
                guard let feat = output.featureValue(for: name),
                      var vec = feat.multiArrayValue?.toFloatArray(), !vec.isEmpty else { continue }
                Self.postProcess(&vec)
                results[origIdx] = vec
                break
            }
        }
        let totalMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return results
    }

    // MARK: - MultiArray input path (most CLIP/MobileCLIP exports)
    // Model expects normalized float tensor [1, 3, H, W] (NCHW) or [1, H, W, 3] (NHWC)

     func extractViaMultiArray(model: MLModel, image: CGImage) -> [Float]? {
        guard let resized = resizeToInput(cgImage: image, width: inputSize, height: inputSize) else {
            return nil
        }

        // Determine expected shape from model
        let desc = model.modelDescription.inputDescriptionsByName[inputName]
        let shape: [Int]
        if let mac = desc?.multiArrayConstraint {
            shape = mac.shape.map { $0.intValue }
        } else {
            shape = [1, 3, inputSize, inputSize]  // default NCHW
        }

        let isNCHW = shape.count == 4 && shape[1] == 3
        // isNHWC: shape[3] == 3

        guard let multiArray = imageToMultiArray(cgImage: resized, shape: shape, nchw: isNCHW) else {
            return nil
        }

        do {
            let featureValue = MLFeatureValue(multiArray: multiArray)
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: featureValue])
            let output = try model.prediction(from: provider)
            for name in output.featureNames {
                if let feat = output.featureValue(for: name), let arr = feat.multiArrayValue?.toFloatArray() {
                    return arr
                }
            }
            return nil
        } catch {
            return nil
        }
    }

     func imageToMultiArray(cgImage: CGImage, shape: [Int], nchw: Bool) -> MLMultiArray? {
        let w = cgImage.width
        let h = cgImage.height
        let bytesPerRow = 4 * w
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // CLIP/MobileCLIP normalization: ImageNet mean/std
        // CoreML exports do NOT bake this in — we must apply it.
        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
        let std: [Float]  = [0.26862954, 0.26130258, 0.27577711]

        guard let multiArray = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32) else {
            return nil
        }

        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        let pixelCount = w * h

        if nchw {
            // Shape: [1, 3, H, W] — contiguous layout: R plane, then G plane, then B plane
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    let pixIdx = y * w + x
                    ptr[pixIdx]                  = (Float(pixels[i])     / 255.0 - mean[0]) / std[0]  // R
                    ptr[pixelCount + pixIdx]     = (Float(pixels[i + 1]) / 255.0 - mean[1]) / std[1]  // G
                    ptr[2 * pixelCount + pixIdx] = (Float(pixels[i + 2]) / 255.0 - mean[2]) / std[2]  // B
                }
            }
        } else {
            // Shape: [1, H, W, 3] (NHWC) — interleaved RGB
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    let base = (y * w + x) * 3
                    ptr[base]     = (Float(pixels[i])     / 255.0 - mean[0]) / std[0]  // R
                    ptr[base + 1] = (Float(pixels[i + 1]) / 255.0 - mean[1]) / std[1]  // G
                    ptr[base + 2] = (Float(pixels[i + 2]) / 255.0 - mean[2]) / std[2]  // B
                }
            }
        }

        return multiArray
    }

    // MARK: - Image/PixelBuffer input path (for models with Image-type input)

     func extractViaPixelBuffer(model: MLModel, image: CGImage) -> [Float]? {
        guard let resized = resizeToInput(cgImage: image, width: inputSize, height: inputSize),
              let buffer = pixelBuffer(from: resized) else {
            return nil
        }
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: buffer)])
            let output = try model.prediction(from: provider)
            for name in output.featureNames {
                if let feat = output.featureValue(for: name), let arr = feat.multiArrayValue?.toFloatArray() {
                    return arr
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

     func resizeToInput(cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        guard srcW > 0, srcH > 0 else { return nil }

        let targetSize = CGSize(width: width, height: height)
        let scale = max(targetSize.width / srcW, targetSize.height / srcH)
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let drawRect = CGRect(
            x: (targetSize.width - scaledW) / 2,
            y: (targetSize.height - scaledH) / 2,
            width: scaledW,
            height: scaledH
        )

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        context.draw(cgImage, in: drawRect)
        return context.makeImage()
    }

     func pixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let w = cgImage.width
        let h = cgImage.height
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let out = buffer else { return nil }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(out),
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(out),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        ctx?.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out
    }
}

 extension MLMultiArray {
    func toFloatArray() -> [Float]? {
        let count = shape.map { $0.intValue }.reduce(1, *)
        guard count > 0 else { return nil }
        // Direct pointer access — 50x faster than per-element self[$0] NSNumber boxing
        if dataType == .float32 {
            let ptr = dataPointer.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count))
        } else if dataType == .double {
            let ptr = dataPointer.bindMemory(to: Double.self, capacity: count)
            return (0..<count).map { Float(ptr[$0]) }
        } else if dataType == .float16 {
            // Float16 needs per-element conversion
            return (0..<count).map { Float(truncating: self[$0]) }
        }
        return nil
    }
}

// MARK: - TFLite MobileNetV3 (feature vector for SQLite + cosine similarity)

#if canImport(TensorFlowLite)
final class TFLiteFeatureExtractor: FeatureVectorExtractor {
    static let shared = TFLiteFeatureExtractor()
     var interpreter: Interpreter?
     let modelName = "MobileNet-v3-Large"
     let inputSize = 224

    var dimension: Int { 1280 }  // typical MobileNetV3-Small global pool size; adjust if your model differs

     init() {
        loadModel()
    }

     func loadModel() {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "tflite") else {
            return
        }
        do {
            let interpreter = try Interpreter(modelPath: url.path)
            try interpreter.allocateTensors()
            self.interpreter = interpreter
        } catch {
        }
    }

    func extractVector(from image: CGImage) -> [Float]? {
        guard let interpreter = interpreter else { return nil }
        guard let resized = resizeToInput(cgImage: image, width: inputSize, height: inputSize),
              let inputData = normalizedPixelData(cgImage: resized) else { return nil }
        do {
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            let outputTensor = try interpreter.output(at: 0)
            return outputTensor.data.withUnsafeBytes { ptr in
                let buf = ptr.bindMemory(to: Float.self)
                return Array(UnsafeBufferPointer(start: buf.baseAddress, count: buf.count))
            }
        } catch {
            return nil
        }
    }

     func resizeToInput(cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        guard srcW > 0, srcH > 0 else { return nil }

        let targetSize = CGSize(width: width, height: height)
        let scale = max(targetSize.width / srcW, targetSize.height / srcH)
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let drawRect = CGRect(
            x: (targetSize.width - scaledW) / 2,
            y: (targetSize.height - scaledH) / 2,
            width: scaledW,
            height: scaledH
        )

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        context.draw(cgImage, in: drawRect)
        return context.makeImage()
    }

     func normalizedPixelData(cgImage: CGImage) -> Data? {
        let w = cgImage.width
        let h = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var pixels = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Normalize to [0,1] or [-1,1] per model; MobileNet often expects [0,1]
        var floats: [Float] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            // MobileNetV3 typically expects [-1, 1] range: (pixel - 127.5) / 127.5
            floats.append((Float(pixels[i]) - 127.5) / 127.5)
            floats.append((Float(pixels[i+1]) - 127.5) / 127.5)
            floats.append((Float(pixels[i+2]) - 127.5) / 127.5)
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
#endif

// MARK: - Unified extractor (CLIP preferred, then TFLite, else nil for Vision fallback)

enum FeatureExtractorProvider {
    /// Prefer CLIP (CoreML 512-dim); else TFLite; else nil -> Vision photo-by-photo.
    static var vectorExtractor: FeatureVectorExtractor? {
        if CLIPFeatureExtractor.shared.isAvailable {
            return CLIPFeatureExtractor.shared
        }
        #if canImport(TensorFlowLite)
        return TFLiteFeatureExtractor.shared
        #else
        return nil
        #endif
    }
}
