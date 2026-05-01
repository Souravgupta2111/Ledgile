import Foundation

class BertTokenizer {
    
    // MARK: - Properties
    
     var vocab: [String: Int] = [:]
     var idsToTokens: [Int: String] = [:]
     let unkToken = "[UNK]"
     let clsToken = "[CLS]"
     let sepToken = "[SEP]"
     let padToken = "[PAD]"
    
    // MARK: - Initialization
    
    init(vocabFileName: String = "vocab", vocabFileExtension: String = "txt") {
        loadVocab(fileName: vocabFileName, fileExtension: vocabFileExtension)
    }
    
     func loadVocab(fileName: String, fileExtension: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        
        // Split by newline
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                vocab[token] = index
                idsToTokens[index] = token
            }
        }
    }
    
    // MARK: - Tokenization

    func tokenize(_ text: String, maxLength: Int = 128) -> [Int] {
        var tokens = [clsToken]
        
        let normalized = text.lowercased()
        // Basic whitespace tokenization
        let words = normalized.components(separatedBy: .whitespacesAndNewlines)
        
        for word in words {
            let subwordTokens = wordPieceTokenize(word)
            tokens.append(contentsOf: subwordTokens)
        }
        
        tokens.append(sepToken)
        
        // Truncate if needed
        if tokens.count > maxLength {
            tokens = Array(tokens.prefix(maxLength - 1)) + [sepToken]
        }
        
        var ids = tokens.compactMap { vocab[$0] ?? vocab[unkToken] }
        
   
        return ids
    }
    
    /// WordPiece tokenization logic
     func wordPieceTokenize(_ word: String) -> [String] {
        if word.isEmpty { return [] }
        
        var tokens: [String] = []
        var start = 0
        
        while start < word.count {
            var end = word.count
            var curSubstr: String? = nil
            
            // Greedily find simple longest matching subword
            var found = false
            while start < end {
                let startIndex = word.index(word.startIndex, offsetBy: start)
                let endIndex = word.index(word.startIndex, offsetBy: end)
                var substr = String(word[startIndex..<endIndex])
                
                if start > 0 {
                    substr = "##" + substr
                }
                
                if vocab[substr] != nil {
                    curSubstr = substr
                    found = true
                    break
                }
                
                end -= 1
            }
            
            if found, let validSubstr = curSubstr {
                tokens.append(validSubstr)
                start = end
            } else {
                // If single char not found, mark as UNK and skip the character
                tokens.append(unkToken)
                start += 1 
            }
        }
        
        return tokens
    }
}
