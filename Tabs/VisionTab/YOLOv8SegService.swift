//  YOLOv8-seg: detection + segmentation mask. No SAM — mask comes only from YOLO.

import CoreML
import UIKit
import Accelerate

/// One detection: bounding box + optional segmentation mask (from YOLOv8-seg only).
struct YOLODetection {
    let rect: CGRect
    let confidence: Float
    let classIndex: Int
    /// Mask same size as model input; use to create transparent crop. Nil if not seg model.
    let mask: (width: Int, height: Int, floats: [Float])?
    
    var className: String {
        Self.cocoLabels.indices.contains(classIndex) ? Self.cocoLabels[classIndex] : "class_\(classIndex)"
    }
    
    static let cocoLabels = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop",
        "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]
}

final class YOLOv8SegService {
    private struct LetterboxInfo {
        let image: CGImage
        let forwardScale: CGFloat
        let inverseScale: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat
        let originalWidth: Int
        let originalHeight: Int
    }

    static let shared = YOLOv8SegService()
     var model: MLModel?
     let queue = DispatchQueue(label: "yolo.seg", qos: .userInitiated)
     let ciContext = CIContext()  // Reuse — CIContext creation is expensive
    /// Common YOLOv8-seg input size
     let inputSize = 640
     let confidenceThreshold: Float = 0.25
     let iouThreshold: Float = 0.45

    var isAvailable: Bool { model != nil }

     init() {
        loadModel()
    }

     func loadModel() {
        let names = ["YOLOv8_seg", "YOLOv8-seg", "yolov8n_seg", "yolov8n-seg"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndNeuralEngine
                    model = try MLModel(contentsOf: url, configuration: config)
                    return
                } catch {
                }
            }
        }
    }

    /// Run detection + segmentation. Returns boxes and masks from YOLOv8-seg only (no SAM).
    func detect(in image: CGImage, completion: @escaping ([YOLODetection]) -> Void) {
        guard let model = model else {
            completion([])
            return
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let prepared = self.letterbox(cgImage: image, size: self.inputSize),
                  let pixelBuffer = self.cgImageToPixelBuffer(prepared.image) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let (boxes, maskProtos) = self.runInference(model: model, pixelBuffer: pixelBuffer)
            let detections = self.parseOutput(
                boxes: boxes,
                maskProtos: maskProtos,
                letterbox: prepared
            )
            DispatchQueue.main.async { completion(detections) }
        }
    }

     func runInference(model: MLModel, pixelBuffer: CVPixelBuffer) -> (boxes: MLMultiArray?, maskProtos: MLMultiArray?) {
        let inputName = model.modelDescription.inputDescriptionsByName.first?.key ?? "image"
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let out = try? model.prediction(from: provider) else {
            return (nil, nil)
        }
        var boxes: MLMultiArray?
        var maskProtos: MLMultiArray?
        for name in out.featureNames {
            guard let feat = out.featureValue(for: name)?.multiArrayValue else { continue }
            let shape = feat.shape.map { $0.intValue }
            // Mask protos are always 4D: [1, 32, H, W] (e.g. [1, 32, 160, 160])
            if shape.count == 4 {
                maskProtos = feat
            // Boxes are 3D: [1, numChannels, numAnchors] (e.g. [1, 116, 8400])
            } else if shape.count == 3 {
                if boxes == nil { boxes = feat }
            }
        }
        // If no 3D output, grab whatever multi-array is available as boxes
        if boxes == nil {
            for name in out.featureNames {
                if let feat = out.featureValue(for: name)?.multiArrayValue, feat !== maskProtos {
                    boxes = feat
                    break
                }
            }
        }
        return (boxes, maskProtos)
    }

    private func parseOutput(boxes: MLMultiArray?, maskProtos: MLMultiArray?, letterbox: LetterboxInfo) -> [YOLODetection] {
        guard let boxes = boxes else { return [] }
        let shape = boxes.shape.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        let numChannels = shape.count == 3 ? shape[1] : shape[0]
        let numAnchors = shape.count == 3 ? shape[2] : shape[1]
        var results: [(rect: CGRect, conf: Float, coeffs: [Float]?, classIdx: Int)] = []

        for a in 0..<numAnchors {
            func at(_ ch: Int) -> Float {
                if shape.count == 3 { return boxes[[0, ch, a] as [NSNumber]].floatValue }
                return boxes[[ch, a] as [NSNumber]].floatValue
            }
            let x = at(0), y = at(1), w = at(2), h = at(3)
            var maxCls: Float = 0
            var maxClsIdx: Int = 0
            for i in 4..<min(numChannels, 84) {
                let v = at(i)
                if v > maxCls { maxCls = v; maxClsIdx = i - 4 }
            }
            if maxCls < confidenceThreshold { continue }
            var coeffs: [Float]?
            if maskProtos != nil, numChannels >= 36 {
                coeffs = (0..<32).map { at(4 + 80 + $0) }
            }
            let rectInModel = CGRect(
                x: CGFloat(x - w / 2),
                y: CGFloat(y - h / 2),
                width: CGFloat(w),
                height: CGFloat(h)
            )
            let r = remapRectFromLetterbox(rectInModel, info: letterbox)
            guard r.width > 1, r.height > 1 else { continue }
            results.append((rect: r, conf: maxCls, coeffs: coeffs, classIdx: maxClsIdx))
        }
        
        let nms = nms(results, iouThreshold: iouThreshold)
        
        var out: [YOLODetection] = []
        for (rect, conf, coeffs, classIdx) in nms {
            if let coeffs = coeffs, let protos = maskProtos {
                let maskFloats = decodeMask(coeffs: coeffs, protos: protos, info: letterbox)
                out.append(YOLODetection(
                    rect: rect,
                    confidence: conf,
                    classIndex: classIdx,
                    mask: (letterbox.originalWidth, letterbox.originalHeight, maskFloats)
                ))
            } else {
                out.append(YOLODetection(rect: rect, confidence: conf, classIndex: classIdx, mask: nil))
            }
        }

        return out
    }

    private func decodeMask(coeffs: [Float], protos: MLMultiArray, info: LetterboxInfo) -> [Float] {
        let shape = protos.shape.map { $0.intValue }
        guard shape.count >= 4 else { return [] }
        let numProtos = min(32, shape[1])
        let H = shape[2], W = shape[3]
        let count = H * W
        var out = [Float](repeating: 0, count: count)
        for i in 0..<min(numProtos, coeffs.count) {
            let c = coeffs[i]
            // Extract one proto channel [H, W] from [1, 32, H, W]
            var channel = [Float](repeating: 0, count: count)
            for y in 0..<H {
                for x in 0..<W {
                    channel[y * W + x] = protos[[0, i, y, x] as [NSNumber]].floatValue
                }
            }
            // out += c * channel
            var coeff = c
            vDSP_vsma(channel, 1, &coeff, out, 1, &out, 1, vDSP_Length(count))
        }
        // Sigmoid: 1 / (1 + exp(-x))
        var negOut = [Float](repeating: 0, count: count)
        var one: Float = 1.0
        vDSP_vneg(out, 1, &negOut, 1, vDSP_Length(count))
        var negCount = Int32(count)
        vvexpf(&negOut, negOut, &negCount)
        vDSP_vsadd(negOut, 1, &one, &negOut, 1, vDSP_Length(count))
        vvrecf(&out, negOut, &negCount)
        var remapped = [Float](repeating: 0, count: info.originalWidth * info.originalHeight)
        let protoScaleX = CGFloat(W) / CGFloat(inputSize)
        let protoScaleY = CGFloat(H) / CGFloat(inputSize)

        for y in 0..<info.originalHeight {
                let modelY = CGFloat(y) * info.forwardScale + info.yOffset
                let py = min(H - 1, max(0, Int(modelY * protoScaleY)))
            for x in 0..<info.originalWidth {
                let modelX = CGFloat(x) * info.forwardScale + info.xOffset
                let px = min(W - 1, max(0, Int(modelX * protoScaleX)))
                remapped[y * info.originalWidth + x] = out[py * W + px]
            }
        }

        return remapped
    }

     func nms(_ input: [(rect: CGRect, conf: Float, coeffs: [Float]?, classIdx: Int)], iouThreshold: Float) -> [(rect: CGRect, conf: Float, coeffs: [Float]?, classIdx: Int)] {
        let sorted = input.sorted { $0.conf > $1.conf }
        var kept: [(rect: CGRect, conf: Float, coeffs: [Float]?, classIdx: Int)] = []
        for s in sorted {
            if kept.contains(where: { s.rect.iou(with: $0.rect) > CGFloat(iouThreshold) }) { continue }
            kept.append(s)
        }
        return kept
    }

    private func letterbox(cgImage: CGImage, size: Int) -> LetterboxInfo? {
        let targetSize = CGSize(width: size, height: size)
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let xOffset = (targetSize.width - scaledSize.width) / 2.0
        let yOffset = (targetSize.height - scaledSize.height) / 2.0

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: xOffset, y: yOffset, width: scaledSize.width, height: scaledSize.height))

        guard let image = context.makeImage() else { return nil }
        return LetterboxInfo(
            image: image,
            forwardScale: scale,
            inverseScale: 1 / scale,
            xOffset: xOffset,
            yOffset: yOffset,
            originalWidth: cgImage.width,
            originalHeight: cgImage.height
        )
    }

    private func remapRectFromLetterbox(_ rect: CGRect, info: LetterboxInfo) -> CGRect {
        let x = max(0, (rect.origin.x - info.xOffset) * info.inverseScale)
        let y = max(0, (rect.origin.y - info.yOffset) * info.inverseScale)
        let width = rect.width * info.inverseScale
        let height = rect.height * info.inverseScale
        let remapped = CGRect(x: x, y: y, width: width, height: height)
        return remapped.intersection(CGRect(x: 0, y: 0, width: info.originalWidth, height: info.originalHeight))
    }

     func cgImageToPixelBuffer(_ cg: CGImage) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, cg.width, cg.height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let out = buffer else { return nil }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(out), width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(out), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return out
    }
}
