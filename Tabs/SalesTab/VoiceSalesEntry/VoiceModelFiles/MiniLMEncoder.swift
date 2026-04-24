import CoreML
import Foundation


class MiniLMEncoder {
    
    static let shared = MiniLMEncoder()
    
     var model: MLModel?
     let tokenizer = BertTokenizer()
     let queue = DispatchQueue(label: "com.tabs.minilm", qos: .userInitiated)
    
    
    let embeddingSize = 384
    
    init() {
        loadModel()
    }
    
     func loadModel() {
        
        guard let url = Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc") else {
            return
        }
        
        do {
            self.model = try MLModel(contentsOf: url)
        } catch {
        }
    }

    
    func encode(_ text: String) -> [Float]? {
        guard let model = model else { return nil }
        
        let fixedLength = 128
        let tokens = tokenizer.tokenize(text, maxLength: fixedLength)
        
        
        guard let inputIdsMultiArray = try? MLMultiArray(shape: [1, NSNumber(value: fixedLength)], dataType: .int32),
              let maskMultiArray = try? MLMultiArray(shape: [1, NSNumber(value: fixedLength)], dataType: .int32) else {
            return nil
        }
        
        for i in 0..<fixedLength {
            inputIdsMultiArray[i] = 0
            maskMultiArray[i] = 0
        }
        
      
        for (i, token) in tokens.enumerated() {
            if i < fixedLength {
                inputIdsMultiArray[i] = NSNumber(value: token)
                maskMultiArray[i] = 1
            }
        }
        
        let inputs: [String: Any] = [
            "input_ids": inputIdsMultiArray,
            "attention_mask": maskMultiArray
        ]
        
        let provider = try? MLDictionaryFeatureProvider(dictionary: inputs)
        guard let inputFeatures = provider,
              let output = try? model.prediction(from: inputFeatures) else {
            return nil
        }
        
       
        if let embeddingOut = output.featureValue(for: "embeddings")?.multiArrayValue ?? 
                              output.featureValue(for: "Identity")?.multiArrayValue {
            return convertMultiArrayToFloat(embeddingOut)
        }
        
        return nil
    }
    
     func convertMultiArrayToFloat(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = array[i].floatValue
        }
        return result
    }
    
    // MARK: - Batch Processing
    
  
    func batchEncode(_ texts: [String], completion: @escaping ([[Float]?]) -> Void) {
        queue.async {
            let results = texts.map { self.encode($0) }
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
}
