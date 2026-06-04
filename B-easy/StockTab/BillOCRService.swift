//  Returns OCRTextBox array with spatial data for column parsing.

import Vision
import UIKit

final class BillOCRService {

    static let shared = BillOCRService()

     init() {}

    func detectTextDensity(in image: CGImage, completion: @escaping (Bool) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            let results = (req.results as? [VNRecognizedTextObservation]) ?? []
            let totalChars = results.reduce(0) { $0 + ($1.topCandidates(1).first?.string.count ?? 0) }
            DispatchQueue.main.async { completion(totalChars > 15) }
        }
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["hi-IN", "en-US"]
        request.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async { completion(false) }
        }
    }

   
    func recognizeTextBoxes(in image: CGImage, completion: @escaping ([OCRTextBox]) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            let results = (req.results as? [VNRecognizedTextObservation]) ?? []
            let boxes: [OCRTextBox] = results.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return OCRTextBox(
                    text: candidate.string,
                    boundingBox: obs.boundingBox,
                    confidence: candidate.confidence
                )
            }
            DispatchQueue.main.async { completion(boxes) }
        }
        request.recognitionLevel = .accurate
        
        request.recognitionLanguages = ["hi-IN", "en-US"]
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async { completion([]) }
        }
    }

   
    func recognizeText(in image: CGImage, completion: @escaping (String) -> Void) {
        recognizeTextBoxes(in: image) { boxes in
            let text = boxes.map { $0.text }.joined(separator: "\n")
            completion(text)
        }
    }

   
    func recognizeTextFromBill(image: UIImage, completion: @escaping ([OCRTextBox]) -> Void) {
        BillPreprocessor.shared.processForOCR(image) { [weak self] cgImage in
            guard let self = self else { return }
            let img = cgImage ?? image.cgImage
            guard let img = img else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self.recognizeTextBoxes(in: img, completion: completion)
        }
    }

    func recognizeTextFromBill(image: UIImage, completion: @escaping (String) -> Void) {
        recognizeTextFromBill(image: image) { (boxes: [OCRTextBox]) in
            let text = boxes.map { $0.text }.joined(separator: "\n")
            completion(text)
        }
    }
}
