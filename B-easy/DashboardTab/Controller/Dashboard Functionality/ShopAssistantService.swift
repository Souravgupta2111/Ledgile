#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
final class ShopAssistantService {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use Assistant."
        case .unavailable(.deviceNotEligible):
            return "This iPhone cannot run Apple Intelligence. Assistant needs a supported device."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            return "Assistant is unavailable. Set the phone language to English (India) and enable Apple Intelligence."
        }
    }

    func reply(to question: String) async throws -> String {
        try await streamReply(to: question, onPartial: { _ in })
    }

    func streamReply(to question: String, onPartial: @escaping (String) -> Void) async throws -> String {
        let finish: (String) -> String = { raw in
            let msg = Self.sanitize(raw)
            onPartial(msg)
            return msg
        }

        if Self.isGreeting(question) {
            return finish(Self.scopeReply)
        }

        onPartial("Fetching...")

        if Self.looksLikeTopSeller(question) {
            return finish(ShopLedgerLookup.topSellingProducts())
        }

        if !ShopLedgerLookup.hasAnyBooks(), Self.looksLikeShopData(question) {
            return finish(ShopLedgerLookup.emptyBooksMessage)
        }

        let parser = LanguageModelSession(tools: [], instructions: Self.parseInstructions)
        let parsed = try await parser.respond(to: question, generating: ShopQuestion.self)
        var ask = parsed.content
        if Self.looksLikeTopSeller(question) {
            ask.kind = .topSellers
        }
        return finish(Self.englishAnswer(for: ask))
    }

    private static let scopeReply =
        "I can only answer from this shop’s B-easy data — sales, stock, udhaar, a customer, or a product. What should I look up?"

    private static func isGreeting(_ question: String) -> Bool {
        let t = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        let greetings: Set<String> = [
            "hi", "hey", "hello", "yo", "bro", "bhai", "bhaiya", "ok", "okay", "haan", "han",
            "thanks", "thank you", "thx", "namaste", "hola", "sup", "helo", "hii", "hiii"
        ]
        return greetings.contains(t)
    }

    private static func looksLikeTopSeller(_ question: String) -> Bool {
        let t = question.lowercased()
        let keys = [
            "most selling", "best selling", "top selling", "best seller", "top product",
            "selling product", "sold the most", "sold most", "highest sale", "max sale",
            "sabse zyada", "sabse jyada", "zyada bika", "bika sabse", "becha sabse", "bika"
        ]
        return keys.contains(where: { t.contains($0) })
    }

    private static func looksLikeShopData(_ question: String) -> Bool {
        let t = question.lowercased()
        let keys = [
            "sale", "sales", "stock", "udhaar", "udhar", "credit", "profit", "bill", "invoice",
            "product", "item", "customer", "supplier", "aaj", "kitna", "kitni", "bika", "becha"
        ]
        return keys.contains(where: { t.contains($0) })
    }

    private static func englishAnswer(for ask: ShopQuestion) -> String {
        switch ask.kind {
        case .smallTalk, .offTopic:
            return scopeReply
        case .writeRefused:
            return "I can only read this shop’s data. To add or edit, use the Sales or Stock tab."
        case .topSellers:
            return ShopLedgerLookup.topSellingProducts()
        case .shopSnapshot:
            return ShopLedgerLookup.friendlyShopSummary()
        case .inventory:
            let q = ask.productQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if q.isEmpty {
                if !ShopLedgerLookup.hasAnyBooks() { return ShopLedgerLookup.emptyBooksMessage }
                return ShopLedgerLookup.searchItems(query: "", limit: 20)
            }
            return ShopLedgerLookup.itemDetail(name: q)
        case .partyLedger:
            let name = ask.partyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { return ShopLedgerLookup.friendlyShopSummary() }
            return ShopLedgerLookup.partyLedger(name: name, months: ask.months ?? 3)
        }
    }

    private static func sanitize(_ text: String) -> String {
        let t = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return ShopLedgerLookup.emptyBooksMessage }
        return t
    }

    private static let parseInstructions = """
    Extract what the shopkeeper wants. Do not answer. Only fill the schema.
    kind=smallTalk for hi, hey, bro, thanks.
    kind=offTopic for anything not about THIS shop’s B-easy data (news, jokes, general knowledge, other apps, religion).
    kind=writeRefused if they ask to add, save, delete, edit, waive, maaf, write off, insert, update, or change any bill, stock, or udhaar.
    kind=partyLedger when they name a person or ask udhaar/udhar/credit/bills of someone. partyName is that person. pichle N mahine -> months=N.
    kind=inventory when they ask stock, rate, barcode, or a named product.
    kind=topSellers when they ask most selling / best selling / sabse zyada bika / top product.
    kind=shopSnapshot when they ask aaj sale, profit, totals, with no person name.
    Example: "pichle 3 mahine ke bill bata kitni hai ramphal ki udhar" -> partyLedger, partyName=Ramphal, months=3.
    """
}
#endif
