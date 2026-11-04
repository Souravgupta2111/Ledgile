import AppIntents

public struct BEasyAppShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor { .teal }

    public init() {}

    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "\(.applicationName) today's sales",
                "\(.applicationName) aaj ki sale",
                "\(.applicationName) aaj ka hisaab",
                "today's sales in \(.applicationName)",
                "aaj ki sale \(.applicationName)"
            ],
            shortTitle: "Today",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: LowStockIntent(),
            phrases: [
                "\(.applicationName) low stock",
                "\(.applicationName) low stock items",
                "\(.applicationName) stock kam hai kya",
                "low stock in \(.applicationName)",
                "stock kam hai kya \(.applicationName)"
            ],
            shortTitle: "Low stock",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: UdhaarSummaryIntent(),
            phrases: [
                "\(.applicationName) udhaar",
                "\(.applicationName) kitna udhaar baaki hai",
                "\(.applicationName) udhaar summary",
                "udhaar in \(.applicationName)",
                "kitna udhaar baaki hai \(.applicationName)"
            ],
            shortTitle: "Udhaar",
            systemImageName: "person.2"
        )
        AppShortcut(
            intent: PartyBalanceIntent(),
            phrases: [
                "\(.applicationName) \(\.$party) ka udhaar",
                "\(.applicationName) \(\.$party) balance",
                "\(\.$party) ka udhaar in \(.applicationName)",
                "\(\.$party) balance in \(.applicationName)"
            ],
            shortTitle: "Party",
            systemImageName: "person.text.rectangle"
        )
        AppShortcut(
            intent: ExpiryIntent(),
            phrases: [
                "\(.applicationName) expiry",
                "\(.applicationName) expiry alerts",
                "\(.applicationName) kya expire ho raha hai",
                "expiring items in \(.applicationName)",
                "expiry alerts \(.applicationName)"
            ],
            shortTitle: "Expiry",
            systemImageName: "calendar.badge.exclamationmark"
        )
        AppShortcut(
            intent: RecentTransactionsIntent(),
            phrases: [
                "\(.applicationName) recent bills",
                "\(.applicationName) pichle bills",
                "\(.applicationName) aakhri bill",
                "recent bills in \(.applicationName)",
                "pichle bills \(.applicationName)"
            ],
            shortTitle: "Recent bills",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: AskShopIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "\(.applicationName) se poocho",
                "Talk to \(.applicationName)",
                "\(.applicationName) assistant"
            ],
            shortTitle: "Ask",
            systemImageName: "sparkles"
        )
    }
}
