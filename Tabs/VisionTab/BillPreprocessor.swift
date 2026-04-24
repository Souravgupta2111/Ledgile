//  Image preprocessing for OCR: auto-rotation, grayscale, adaptive binarization,
//  sharpening, and contrast enhancement. Optimized for handwritten Hindi bills.

import UIKit
import CoreImage
import Vision

#if canImport(OpenCV)
import OpenCV
#endif

final class BillPreprocessor {

    static let shared = BillPreprocessor()

     let ciContext = CIContext(options: [.useSoftwareRenderer: false])

     init() {}
    func processForOCR(_ image: UIImage, completion: @escaping (CGImage?) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.fullPipeline(cgImage: cgImage) ?? cgImage
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Full Pipeline

     func fullPipeline(cgImage: CGImage) -> CGImage? {
        let start = CFAbsoluteTimeGetCurrent()

        let oriented = autoRotateForText(cgImage: cgImage) ?? cgImage
        
        // Deskew: detect text line angles and rotate to straighten the image
        let deskewed = deskewImage(cgImage: oriented) ?? oriented

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[BillPreprocessor] Preprocessing complete in \(String(format: "%.0f", elapsed))ms")

        return deskewed
    }
    
    // MARK: - Deskew (Straighten Tilted Text)
    
    /// Detects the dominant text-line angle using Vision text rectangles
    /// and rotates the image to compensate, straightening tilted receipts.
    func deskewImage(cgImage: CGImage) -> CGImage? {
        // Use VNRecognizeTextRequest to get text observations with bounding boxes
        let semaphore = DispatchSemaphore(value: 0)
        var observations: [VNRecognizedTextObservation] = []
        
        let request = VNRecognizeTextRequest { req, _ in
            observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            semaphore.signal()
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        semaphore.wait()
        
        guard observations.count >= 3 else {
            // Not enough text to determine skew
            return nil
        }
        
        // Compute the angle of each text observation's bounding box
        // Vision returns boundingBox in normalized coordinates (0..1), origin bottom-left
        var angles: [CGFloat] = []
        
        for obs in observations {
            // Get the recognized text to determine width (multi-char lines are more reliable)
            guard let text = obs.topCandidates(1).first?.string,
                  text.count >= 3 else { continue }
            
            // Use the observation's bounding box to estimate angle
            // The topLeft and topRight corners give us the text baseline angle
            guard let topLeft = try? obs.topCandidates(1).first?.boundingBox(for: obs.topCandidates(1).first!.string.startIndex..<obs.topCandidates(1).first!.string.endIndex) else {
                continue
            }
            
            let boxTopLeft = topLeft.topLeft
            let boxTopRight = topLeft.topRight
            
            let dx = boxTopRight.x - boxTopLeft.x
            let dy = boxTopRight.y - boxTopLeft.y
            
            // Only consider lines with meaningful horizontal extent
            guard abs(dx) > 0.05 else { continue }
            
            let angle = atan2(dy, dx)  // Radians
            angles.append(angle)
        }
        
        guard angles.count >= 2 else { return nil }
        
        // Compute median angle (robust to outliers)
        let sortedAngles = angles.sorted()
        let medianAngle = sortedAngles[sortedAngles.count / 2]
        
        // Convert to degrees for logging
        let angleDegrees = medianAngle * 180.0 / .pi
        
        // Only deskew if the tilt is between 1° and 30° — below 1° is noise,
        // above 30° is probably a different orientation entirely
        guard abs(angleDegrees) > 1.0 && abs(angleDegrees) < 30.0 else {
            print("[BillPreprocessor] Skew angle \(String(format: "%.1f", angleDegrees))° — no correction needed")
            return nil
        }
        
        print("[BillPreprocessor] Detected skew: \(String(format: "%.1f", angleDegrees))°, applying correction")
        
        // Rotate the image by -medianAngle to straighten it
        let ciImage = CIImage(cgImage: cgImage)
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: -medianAngle))
        
        // The rotation may shift the image origin to negative coordinates; recenter it
        let translatedBack = rotated.transformed(by: CGAffineTransform(
            translationX: -rotated.extent.origin.x,
            y: -rotated.extent.origin.y
        ))
        
        return ciContext.createCGImage(translatedBack, from: translatedBack.extent)
    }

    // MARK: - Grayscale

     func convertToGrayscale(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPhotoEffectNoir") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    // MARK: - Sharpen

     func applySharpen(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.5, forKey: kCIInputRadiusKey)      // Radius of sharpening
        filter.setValue(0.8, forKey: kCIInputIntensityKey)    // Strength of sharpening
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    // MARK: - Adaptive Contrast (CLAHE-like)

     func applyAdaptiveContrast(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        // Boost contrast more aggressively for bills
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(ciImage, forKey: kCIInputImageKey)
        controls.setValue(1.5, forKey: kCIInputContrastKey)
        controls.setValue(0.05, forKey: kCIInputBrightnessKey)
        guard let step1 = controls.outputImage else { return nil }

        // Apply exposure adjustment to brighten dark areas
        guard let exposure = CIFilter(name: "CIExposureAdjust") else {
            return ciContext.createCGImage(step1, from: step1.extent)
        }
        exposure.setValue(step1, forKey: kCIInputImageKey)
        exposure.setValue(0.3, forKey: kCIInputEVKey)
        guard let output = exposure.outputImage else {
            return ciContext.createCGImage(step1, from: step1.extent)
        }
        return ciContext.createCGImage(output, from: output.extent)
    }

    // MARK: - Binarization (Thresholding)

   
     func applyBinarization(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        if #available(iOS 17.0, *) {
            if let filter = CIFilter(name: "CIColorThresholdOtsu") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    return ciContext.createCGImage(output, from: output.extent)
                }
            }
        }

        
        guard let clamp = CIFilter(name: "CIColorClamp") else { return nil }
        clamp.setValue(ciImage, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        guard let clamped = clamp.outputImage else { return nil }

        // High contrast to simulate binarization
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(clamped, forKey: kCIInputImageKey)
        controls.setValue(3.0, forKey: kCIInputContrastKey)   // Very high contrast
        controls.setValue(-0.1, forKey: kCIInputBrightnessKey)
        guard let output = controls.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    // MARK: - Auto-Rotation

   
     func autoRotateForText(cgImage: CGImage) -> CGImage? {
        let orientations: [(CGImagePropertyOrientation, String)] = [
            (.up, "0°"), (.right, "90°"), (.down, "180°"), (.left, "270°")
        ]

        var bestImage = cgImage
        var bestCount = countTextRegions(cgImage: cgImage, orientation: .up)

        if bestCount >= 5 { return cgImage }

        for (orient, label) in orientations.dropFirst() {
            let count = countTextRegions(cgImage: cgImage, orientation: orient)
            if count > bestCount {
                bestCount = count
                if let rotated = rotateImage(cgImage, orientation: orient) {
                    bestImage = rotated
                }
            }
        }
        return bestImage
    }

     func countTextRegions(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> Int {
        let semaphore = DispatchSemaphore(value: 0)
        var count = 0
        let request = VNRecognizeTextRequest { request, _ in
            count = request.results?.count ?? 0
            semaphore.signal()
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform([request])
        semaphore.wait()
        return count
    }

     func rotateImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation.rawValue))
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}
