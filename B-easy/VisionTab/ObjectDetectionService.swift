import UIKit
import CoreImage
import Vision

struct DetectedObjectBox {
    let rect: CGRect
    let confidence: Float
    let mask: (width: Int, height: Int, floats: [Float])?
}

protocol ObjectDetectionServiceProtocol {
    func detectObjects(in image: CGImage, completion: @escaping ([DetectedObjectBox]) -> Void)
}

final class ObjectDetectionService: ObjectDetectionServiceProtocol {

    static let shared = ObjectDetectionService()
    init() {}

    func detectObjects(in image: CGImage, completion: @escaping ([DetectedObjectBox]) -> Void) {
        var allBoxes: [DetectedObjectBox] = []
        let lock = NSLock()
        let group = DispatchGroup()

        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest { req, error in
            if let result = req.results?.first as? VNSaliencyImageObservation,
               let objects = result.salientObjects {

                let w = CGFloat(image.width)
                let h = CGFloat(image.height)
                let imageArea = w * h

                let saliencyBoxes = objects.map { obj -> DetectedObjectBox in
                    let r = obj.boundingBox
                    let rect = VNImageRectForNormalizedRect(r, Int(w), Int(h))
                    let flippedY = h - rect.maxY
                    let finalRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
                    let areaFraction = Float((finalRect.width * finalRect.height) / imageArea)
                    let conf = min(0.6, max(0.15, areaFraction * 2.0))
                    return DetectedObjectBox(rect: finalRect, confidence: conf, mask: nil)
                }
                lock.lock()
                allBoxes.append(contentsOf: saliencyBoxes)
                lock.unlock()
            }
        }

        let rectRequest = VNDetectRectanglesRequest { req, error in
            if let results = req.results as? [VNRectangleObservation] {
                let w = CGFloat(image.width)
                let h = CGFloat(image.height)

                let rectBoxes = results.map { obj -> DetectedObjectBox in
                    let r = obj.boundingBox
                    let rect = VNImageRectForNormalizedRect(r, Int(w), Int(h))
                    let flippedY = h - rect.maxY
                    let finalRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
                    return DetectedObjectBox(rect: finalRect, confidence: min(1.0, obj.confidence + 0.3), mask: nil)
                }
                lock.lock()
                allBoxes.append(contentsOf: rectBoxes)
                lock.unlock()
            }
        }
        rectRequest.minimumSize = 0.1
        rectRequest.maximumObservations = 10
        rectRequest.minimumConfidence = 0.4

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                try handler.perform([saliencyRequest, rectRequest])
            } catch {
                print("[ObjectDetection] Vision fallback failed: \(error.localizedDescription)")
            }
        }

        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            let finalBoxes = self.filterUsableBoxes(self.mergeOverlappingBoxes(allBoxes), image: image)
            completion(Array(finalBoxes.prefix(12)))
        }
    }

    func mergeOverlappingBoxes(_ boxes: [DetectedObjectBox]) -> [DetectedObjectBox] {
        let sorted = boxes.sorted { $0.confidence > $1.confidence }
        var kept: [DetectedObjectBox] = []
        var active = sorted
        let localIoUThreshold: CGFloat = 0.65

        while !active.isEmpty {
            let current = active.removeFirst()
            kept.append(current)

            active.removeAll { box in
                let iou = intersectionOverUnion(current.rect, box.rect)
                let ioMin = intersectionOverMinArea(current.rect, box.rect)
                return iou > localIoUThreshold || ioMin > 0.90
            }
        }

        return kept
    }

    private func filterUsableBoxes(_ boxes: [DetectedObjectBox], image: CGImage) -> [DetectedObjectBox] {
        let imageArea = CGFloat(image.width * image.height)
        guard imageArea > 0 else { return [] }

        let filtered = boxes.filter { box in
            let rect = box.rect.standardized
            guard rect.width > 24, rect.height > 24 else { return false }
            let areaRatio = (rect.width * rect.height) / imageArea
            guard areaRatio >= 0.012 && areaRatio <= 0.72 else { return false }
            // Carpet stripes / table edges: very elongated saliency blobs are rarely packs.
            let aspect = max(rect.width, rect.height) / max(1, min(rect.width, rect.height))
            if aspect > 3.8 { return false }
            return true
        }

        return filtered.sorted { lhs, rhs in
            let lhsArea = lhs.rect.width * lhs.rect.height
            let rhsArea = rhs.rect.width * rhs.rect.height
            if abs(lhs.confidence - rhs.confidence) > 0.05 {
                return lhs.confidence > rhs.confidence
            }
            return lhsArea > rhsArea
        }
    }

    func intersectionOverUnion(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
        let intersection = r1.intersection(r2)
        let interArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let area1 = r1.width * r1.height
        let area2 = r2.width * r2.height
        let unionArea = area1 + area2 - interArea
        if unionArea <= 0 { return 0 }
        return interArea / unionArea
    }

    func intersectionOverMinArea(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
        let intersection = r1.intersection(r2)
        let interArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let area1 = r1.width * r1.height
        let area2 = r2.width * r2.height
        let minArea = min(area1, area2)
        if minArea <= 0 { return 0 }
        return interArea / minArea
    }
}
