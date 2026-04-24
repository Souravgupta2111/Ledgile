import Foundation

class UserAliasManager {
    static let shared = UserAliasManager()
    
     let userDefaultsKey = "Com.Tabs.UserAliases"
     var aliases: [String: String] = [:]
    
     init() {
        loadAliases()
    }
    
     func loadAliases() {
        if let stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] {
            self.aliases = stored
        }
    }
    
    
    func learnAlias(term: String, canonical: String) {
        let normalizedTerm = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCanonical = canonical.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedTerm.isEmpty, !normalizedCanonical.isEmpty, normalizedTerm != normalizedCanonical else { return }
        
        aliases[normalizedTerm] = normalizedCanonical
        saveAliases()
    }
    
   
    func getCanonical(for term: String) -> String? {
        let normalizedTerm = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases[normalizedTerm]
    }
    
     func saveAliases() {
        UserDefaults.standard.set(aliases, forKey: userDefaultsKey)
    }
}
