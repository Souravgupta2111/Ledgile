import Foundation

final class BarcodeMatcher {

    static let shared = BarcodeMatcher()
    private init() {}

    struct MatchResult {
        let item: Item
        let confidence: Double
        let reason: String
    }
    
    func findMatches(for productName: String, in items: [Item]) -> [MatchResult] {
        let normalizedSearch = normalize(productName)
        guard !normalizedSearch.isEmpty else { return [] }
        let searchTokens = Set(normalizedSearch.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        var results: [MatchResult] = []

        for item in items {
            let normalizedItem = normalize(item.name)
            if normalizedItem.isEmpty { continue }
            if normalizedSearch == normalizedItem {
                results.append(MatchResult(item: item, confidence: 1.0, reason: "Exact Match"))
                continue
            }
            let itemTokens = Set(normalizedItem.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
            let intersection = searchTokens.intersection(itemTokens)
            let smallestSetCount = min(searchTokens.count, itemTokens.count)

            if !intersection.isEmpty {
                let overlapRatio = Double(intersection.count) / Double(smallestSetCount)

                if overlapRatio >= 0.5 {
                    let lengthPenalty = abs(Double(searchTokens.count - itemTokens.count)) * 0.05
                    let finalConfidence = max(0.1, overlapRatio - lengthPenalty)

                    let matchHint = intersection.first?.capitalized ?? "Overlap"
                    results.append(MatchResult(item: item, confidence: finalConfidence, reason: "Keyword: \(matchHint)"))
                    continue
                }
            }

        
            let distance = levenshteinDistance(normalizedSearch, normalizedItem)
            let maxLength = max(normalizedSearch.count, normalizedItem.count)
            let similarityScore = 1.0 - (Double(distance) / Double(maxLength))

            if similarityScore > 0.70 {
                results.append(MatchResult(item: item, confidence: similarityScore, reason: "Similar Spelling"))
                continue
            }
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

     private func normalize(_ string: String) -> String {
        var lower = string.lowercased()
        let charactersToRemove = CharacterSet.punctuationCharacters.union(.symbols)
        lower = lower.components(separatedBy: charactersToRemove).joined(separator: "")
        return lower.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }


    private func levenshteinDistance(_ source: String, _ target: String) -> Int {
        let a = Array(source)
        let b = Array(target)

        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,
                        matrix[i][j - 1] + 1,
                        matrix[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return matrix[a.count][b.count]
    }
}
