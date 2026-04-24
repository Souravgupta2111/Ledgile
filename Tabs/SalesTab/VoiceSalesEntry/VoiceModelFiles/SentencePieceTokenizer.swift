//  Real SentencePiece tokenizer matching HuggingFace's is_split_into_words=True behavior

import Foundation
import CoreML

final class SentencePieceTokenizer {
    
    static let shared = SentencePieceTokenizer()
    
    // Vocab: token -> (id, score)
     var vocab: [String: (id: Int, score: Float)] = [:]
     var idToToken: [Int: String] = [:]
     let maxLen = 128
    
    // Special tokens
     let padId = 0
     let unkId = 1
     let clsId = 2
     let sepId = 3
    
     var isLoaded = false
    
    init() {
        loadVocab()
    }
    
     func loadVocab() {
        
        guard let url = Bundle.main.url(forResource: "spiece", withExtension: "vocab") else {
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            for (index, line) in lines.enumerated() {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count >= 1 {
                    let token = String(parts[0])
                    let score: Float = parts.count > 1 ? Float(parts[1]) ?? 0.0 : 0.0
                    vocab[token] = (id: index, score: score)
                    idToToken[index] = token
                }
            }
            
            isLoaded = true
            
        } catch {
        }
    }
    
    func tokenize(text: String) -> ([String], MLMultiArray, MLMultiArray) {
        
        var tokens: [Int] = [clsId]
        var tokenStrings: [String] = ["[CLS]"]
        
       
        let lowercased = text.lowercased()
        
        let words = lowercased.split(separator: " ").map { String($0) }
      
        for word in words {
            let prefixedWord = "▁" + word
            let wordTokens = tokenizeWord(prefixedWord)
            
            for (tokenStr, tokenId) in wordTokens {
                tokens.append(tokenId)
                tokenStrings.append(tokenStr)
            }
        }
        
        tokens.append(sepId)
        tokenStrings.append("[SEP]")
        
        // Pad to maxLen
        let activeCount = min(tokens.count, maxLen)
        while tokens.count < maxLen {
            tokens.append(padId)
            tokenStrings.append("<pad>")
        }
        if tokens.count > maxLen {
            tokens = Array(tokens.prefix(maxLen))
            tokenStrings = Array(tokenStrings.prefix(maxLen))
        }
        
        let inputIds = try! MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        let attentionMask = try! MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        
        for i in 0..<maxLen {
            inputIds[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: tokens[i])
            attentionMask[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: i < activeCount ? 1 : 0)
        }
        
        return (tokenStrings, inputIds, attentionMask)
    }
    
  
     func tokenizeWord(_ word: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        let chars = Array(word)
        var i = 0
        
        while i < chars.count {
            var bestMatch: (token: String, id: Int, len: Int)?
            let maxLen = min(25, chars.count - i)
            
            // Greedy longest match
            for len in stride(from: maxLen, through: 1, by: -1) {
                let substr = String(chars[i..<(i + len)])
                if let entry = vocab[substr] {
                    bestMatch = (token: substr, id: entry.id, len: len)
                    break
                }
            }
            
            if let match = bestMatch {
                result.append((match.token, match.id))
                i += match.len
            } else {
                // Unknown character
                result.append((String(chars[i]), unkId))
                i += 1
            }
        }
        
        return result
    }
    

    static func tokenize(text: String) throws -> ([String], MLMultiArray, MLMultiArray) {
        return shared.tokenize(text: text)
    }
}
