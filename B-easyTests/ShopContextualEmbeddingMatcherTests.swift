import XCTest
@testable import B_easy

final class ShopContextualEmbeddingMatcherTests: XCTestCase {

    var matcher: ShopContextualEmbeddingMatcher {
        ShopContextualEmbeddingMatcher.shared
    }

    func testWarmupDoesNotCrash() {
        matcher.warmup()
    }

    func testTodaySummaryPhrases() {
        let queries = [
            "today sales",
            "today's sales and profit",
            "what is today's revenue",
            "how much did I sell today",
            "aaj ki sale",
            "aaj kitna bika",
            "aaj ka hisaab",
            "aaj kitne bill bane",
            "aaj ka dhandha kaisa raha",
            "aaj ka munafa kitna hai",
            "आज की कुल बिक्री और मुनाफा",
            "आज कितना सामान बिका"
        ]

        for q in queries {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .todaySummary, "Failed on query: '\(q)'")
        }
    }

    func testUdhaarSummaryPhrases() {
        let queries = [
            "total udhaar",
            "kitna udhaar baaki hai",
            "bazaar me kitna paisa phasa hai",
            "market udhaar",
            "who owes me money",
            "total receivables and payables",
            "kitna lena hai aur kitna dena hai",
            "कुल कितना उधार बाकी है",
            "मार्केट में कितना पैसा फंसा है"
        ]

        for q in queries {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .udhaarSummary, "Failed on query: '\(q)'")
        }
    }

    func testLowStockPhrases() {
        let queries = [
            "low stock",
            "stock kam hai kya",
            "kaunsa saaman khatam ho raha hai",
            "restock alerts",
            "which items are running low",
            "khatam hone wala maal",
            "कौन सा सामान खत्म हो रहा है",
            "कम स्टॉक वाले आइटम"
        ]

        for q in queries {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .lowStock, "Failed on query: '\(q)'")
        }
    }

    func testExpiryPhrases() {
        let queries = [
            "expiry alerts",
            "kya expire ho raha hai",
            "kiski expiry paas hai",
            "items expiring soon",
            "date nikalne wali hai",
            "expired batches",
            "क्या एक्सपायर हो रहा है",
            "एक्सपायरी अलर्ट्स दिखाओ"
        ]

        for q in queries {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .expiry, "Failed on query: '\(q)'")
        }
    }

    func testRecentTransactionsPhrases() {
        let queries = [
            "recent transactions",
            "recent bills",
            "aakhri bill kitne ka tha",
            "pichle bills dikhao",
            "last sale bill",
            "last transaction",
            "हाल के बिल दिखाओ",
            "आखिरी बिल कितने का था"
        ]

        for q in queries {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .recentTransactions, "Failed on query: '\(q)'")
        }
    }

    func testPartyBalanceExtraction() {
        let cases: [(String, String)] = [
            ("Ramesh ka udhaar", "Ramesh"),
            ("Suresh ka balance", "Suresh"),
            ("how much does Ramesh owe", "Ramesh"),
            ("balance of Sharma Traders", "Sharma Traders"),
            ("रमेश का कितना उधार है", "रमेश"),
            ("Gupta Stores ka khata", "Gupta Stores"),
            ("udhaar of Verma", "Verma")
        ]

        for (query, expectedParty) in cases {
            let result = matcher.match(query: query)
            XCTAssertEqual(result, .partyBalance(partyName: expectedParty), "Failed on query: '\(query)'")
        }
    }

    func testUnknownQueriesReturnUnknown() {
        let unknowns = [
            "",
            "   ",
            "what is the weather today in Delhi",
            "play some music",
            "tell me a joke"
        ]

        for q in unknowns {
            let result = matcher.match(query: q)
            XCTAssertEqual(result, .unknown, "Expected unknown for query: '\(q)'")
        }
    }
}
