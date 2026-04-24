
import Foundation
import CoreML

final class Tokenizer {
    
    static let shared = Tokenizer()
    
     var vocabulary: [String: Int] = [:]
     let maxLen = 128
    
    // Special tokens (loaded from special_tokens.json)
     var unkToken = "<unk>"
     var clsToken = "[CLS]"
     var sepToken = "[SEP]"
     var padToken = "<pad>"
    
  
     var unkId = 1    // <unk> token ID
     var clsId = 2    // [CLS] token ID
     var sepId = 3    // [SEP] token ID
     var padId = 0    // <pad> token ID
    
     var isVocabLoaded = false
    
    init() {
        loadSpecialTokens()
        loadVocabulary()
    }
    
   
     func loadSpecialTokens() {
        
        // Try to find special_tokens.json in bundle
        if let url = Bundle.main.url(forResource: "special_tokens", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    if let id = json["cls_token_id"] as? Int { clsId = id }
                    if let id = json["sep_token_id"] as? Int { sepId = id }
                    if let id = json["pad_token_id"] as? Int { padId = id }
                    if let id = json["unk_token_id"] as? Int { unkId = id }
                    
                    if let token = json["cls_token"] as? String { clsToken = token }
                    if let token = json["sep_token"] as? String { sepToken = token }
                    if let token = json["pad_token"] as? String { padToken = token }
                    if let token = json["unk_token"] as? String { unkToken = token }
                    
                }
            } catch {
            }
        } else {
        }
    }
    
     func loadVocabulary() {
        
        // Try loading vocab.txt first (standard BERT format)
        if let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                for (index, line) in lines.enumerated() {
                    let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        vocabulary[token] = index
                    }
                }
                isVocabLoaded = true
            } catch {
            }
        }
        

        if !isVocabLoaded, let url = Bundle.main.url(forResource: "vocab", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                if let jsonVocab = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Int] {
                    self.vocabulary = jsonVocab
                    isVocabLoaded = true
                    
                    // Show sample tokens
                    let sampleTokens = Array(vocabulary.prefix(10))
                }
            } catch {
            }
        }
        
        if !isVocabLoaded {
        }
        
    }
    
    static func tokenize(text: String) throws -> ([String], MLMultiArray, MLMultiArray) {
        return Tokenizer.shared.tokenizeText(text)
    }
    
    func tokenizeText(_ text: String) -> ([String], MLMultiArray, MLMultiArray) {
        
        var tokens: [Int] = []
        var tokenStrings: [String] = []
        
        tokens.append(clsId)
        tokenStrings.append(clsToken)
        
        // SentencePiece Normalization
        let normalizedText = text.lowercased().replacingOccurrences(of: " ", with: "▁")
        let spText = "▁" + normalizedText.trimmingCharacters(in: CharacterSet(charactersIn: "▁"))
        
        if isVocabLoaded {
            let chars = Array(spText)
            var i = 0
            while i < chars.count {
                var matchFound = false
                
                // Greedy Longest-Match
               
                var j = chars.count
                if j - i > 25 { j = i + 25 }
                
                while j > i {
                    let subStr = String(chars[i..<j])
                    if let id = vocabulary[subStr] {
                        tokens.append(id)
                        tokenStrings.append(subStr)
                        i = j
                        matchFound = true
                        break
                    }
                    j -= 1
                }
                
                if !matchFound {
                    // Unknown character/subsequence
                    tokens.append(unkId)
                    tokenStrings.append(String(chars[i]))
                    i += 1
                }
            }
        } else {
           
             let words = text.split(separator: " ")
             for word in words {
                 tokens.append(1)
                 tokenStrings.append(String(word))
             }
        }
        
        tokens.append(sepId)
        tokenStrings.append(sepToken)
        
        
        if tokens.count > maxLen {
            tokens = Array(tokens.prefix(maxLen))
            tokenStrings = Array(tokenStrings.prefix(maxLen))
            
            tokens[maxLen - 1] = sepId
            tokenStrings[maxLen - 1] = sepToken
        } else {
            let paddingNeeded = maxLen - tokens.count
            while tokens.count < maxLen {
                tokens.append(padId)
                tokenStrings.append(padToken)
            }
        }
        
        let inputIds = try! MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        let attentionMask = try! MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        
        var activeTokenCount = 0
        for (i, token) in tokens.enumerated() {
            inputIds[i] = NSNumber(value: token)
            
            // Standard Mask: 1 for active, 0 for padding
            let maskVal = token != padId ? 1 : 0
            
            attentionMask[i] = NSNumber(value: maskVal)
            if token != padId { activeTokenCount += 1 }
        }
        
        return (tokenStrings, inputIds, attentionMask)
    }
}
