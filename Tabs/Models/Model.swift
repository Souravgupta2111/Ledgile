import Foundation

// MARK: - ITEM
struct Item: Identifiable, Codable, Equatable {
    let id: UUID

    // Identity
    var name: String
    var unit: String
    var barcode: String? = nil
    var defaultCostPrice: Double
    var defaultSellingPrice: Double
    var defaultPriceUpdatedAt: Date

    // Inventory helpers
    var lowStockThreshold: Int
    var currentStock: Int
 
    let createdDate: Date
    var lastRestockDate: Date?
    var isActive: Bool
    var salesCount: Int? = nil
    var salesTier: Int? = nil

    // GST fields (all optional — no impact on existing items)
    var hsnCode: String? = nil       // e.g., "19021100"
    var gstRate: Double? = nil       // e.g., 18.0 (percent)
    var cessRate: Double? = nil      // e.g., 12.0 (for tobacco, aerated drinks)

    var effectiveSalesTier: Int { salesTier ?? 2 }
    var effectiveSalesCount: Int { salesCount ?? 0 }

    var isLowStock: Bool {
        currentStock <= lowStockThreshold
    }
}


struct ItemBatch: Identifiable, Codable, Equatable {
    let id: UUID
    let itemID: UUID                    // FK → Item.id
    let purchaseTransactionID: UUID     // FK → Transaction.id

    let quantityPurchased: Int
    var quantityRemaining: Int

    let costPrice: Double
    let sellingPrice: Double
    let expiryDate: Date?

    let receivedDate: Date
    

    
    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date()
    }
    
    var daysUntilExpiry: Int? {
        guard let expiry = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}


struct ProductPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let itemID: UUID
    let localPath: String
    let createdAt: Date
}

// MARK: - SALE ITEM BATCH (FIFO Audit Trail)
struct SaleItemBatch: Identifiable, Codable, Equatable {
    let id: UUID
    let transactionItemID: UUID      // FK → TransactionItem.id
    let batchID: UUID                 // FK → ItemBatch.id
    
    let quantityConsumed: Int
    let costPriceUsed: Double
    let sellingPriceUsed: Double
    
    let batchReceivedDate: Date
    let batchExpiryDate: Date?
    
    // MARK: - Computed
    
    var profit: Double {
        Double(quantityConsumed) * (sellingPriceUsed - costPriceUsed)
    }
    
    var revenue: Double {
        Double(quantityConsumed) * sellingPriceUsed
    }
}

// MARK: - TRANSACTIONS

enum TransactionType: String, Codable {
    case sale = "Sale"
    case purchase = "Purchase"
}
struct Transaction: Identifiable, Codable, Equatable {
    let id: UUID
    let type: TransactionType
    let date: Date
    let invoiceNumber: String
    var customerName: String?
    var customerPhone: String?
    var supplierName: String?
    let totalAmount: Double
    var notes: String?

    // GST fields (all optional)
    var buyerGSTIN: String? = nil
    var placeOfSupply: String? = nil         // "Maharashtra"
    var placeOfSupplyCode: String? = nil     // "27"
    var isInterState: Bool? = nil
    var totalTaxableValue: Double? = nil
    var totalCGST: Double? = nil
    var totalSGST: Double? = nil
    var totalIGST: Double? = nil
    var totalCess: Double? = nil
    var isReverseCharge: Bool? = nil
}

struct TransactionItem: Identifiable, Codable, Equatable {
    let id: UUID
    let transactionID: UUID             // FK → Transaction.id
    let itemID: UUID                    // FK → Item.id
    let itemName: String
    let unit: String
    let quantity: Int
    let sellingPricePerUnit: Double?
    let costPricePerUnit: Double?
    let createdDate: Date

    // GST fields (all optional)
    var hsnCode: String? = nil
    var gstRate: Double? = nil
    var taxableValue: Double? = nil       // Price before tax
    var cgstAmount: Double? = nil         // Central GST
    var sgstAmount: Double? = nil         // State GST
    var igstAmount: Double? = nil         // Integrated GST (inter-state)
    var cessAmount: Double? = nil

    var totalRevenue: Double {
        guard let price = sellingPricePerUnit else { return 0 }
        return Double(quantity) * price
    }
    
    var totalCost: Double {
        guard let price = costPricePerUnit else { return 0 }
        return Double(quantity) * price
    }
    
    var profit: Double {
        guard let sell = sellingPricePerUnit, let cost = costPricePerUnit else { return 0 }
        return Double(quantity) * (sell - cost)
    }
    
    var profitMargin: Double {
        guard let sell = sellingPricePerUnit, sell > 0 else { return 0 }
        return (profit / totalRevenue) * 100
    }
}

struct DailySummary: Identifiable, Codable {
    let id: UUID
    let date: Date

    let totalRevenue: Double
    let totalProfit: Double
    let salesTransactionCount: Int
    let itemsSoldCount: Int

    let totalPurchaseAmount: Double
    let purchaseTransactionCount: Int

    var profitMargin: Double {
        guard totalRevenue > 0 else { return 0 }
        return (totalProfit / totalRevenue) * 100
    }
}

struct ItemSalesStats {
    let itemID: UUID
    let itemName: String
    let quantitySold: Int
    let totalRevenue: Double
    let totalProfit: Double
    let profitMargin: Double
    let transactionCount: Int
    let averageSellingPrice: Double
}

struct ItemProfitStats {
    let itemID: UUID
    let itemName: String
    let totalProfit: Double
    let profitPercentage: Double
    let quantitySold: Int
    let profitPerUnit: Double
}

struct TodaySnapshot {
    let date: Date
    let revenue: Double
    let profit: Double
    let profitMargin: Double
    let itemsSold: Int
    let transactionCount: Int

    let revenueChange: Double
    let revenueChangePercent: Double
}

struct RecentTransactionRow: Identifiable {
    let id: UUID
    let type: TransactionType
    let date: Date
    let invoiceNumber: String
    let itemsSummary: String
    let totalAmount: Double
    let customerOrSupplier: String?
}

struct ChartDataPoint: Identifiable {
    let id: UUID
    let date: Date
    let label: String
    let value: Double

    init(id: UUID = UUID(), date: Date, label: String, value: Double) {
        self.id = id
        self.date = date
        self.label = label
        self.value = value
    }
}

struct ExpiryAlert: Identifiable {
    let id: UUID
    let itemID: UUID
    let itemName: String
    let batchID: UUID
    let quantityRemaining: Int
    let expiryDate: Date
    let daysUntilExpiry: Int
    let severity: ExpirySeverity
    
    enum ExpirySeverity: Int, Comparable {
        case expired = 0
        case critical = 1
        case warning = 2
        case notice = 3
        
        static func < (lhs: ExpirySeverity, rhs: ExpirySeverity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

struct LowStockAlert: Identifiable {
    let id: UUID
    let itemID: UUID
    let itemName: String
    let currentStock: Int
    let threshold: Int
    let unit: String
}

enum TimeRange: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
}

struct AppSettings: Codable {
    var invoicePrefix: String
    var invoiceNumberCounter: Int
    var currentYear: Int?
    var includeYearInInvoice: Bool

    var ownerName: String?
    var businessName: String
    var profileName: String?
    var businessPhone: String?
    var profileImageData: Data?
    var businessAddress: String?
    var gstNumber: String?
    
    var expiryNoticeDays: Int       // 14 days
    var expiryWarningDays: Int      // 7 days
    var expiryCriticalDays: Int     // 3 days

    // GST configuration fields
    var isGSTRegistered: Bool = false          // MASTER TOGGLE
    var gstScheme: String? = nil               // "regular" or "composition"
    var businessState: String? = nil           // "Maharashtra"
    var businessStateCode: String? = nil       // "27"
    var pricesIncludeGST: Bool = true          // Default: MRP inclusive
    var defaultGSTRate: Double? = nil          // Most used rate (e.g., 18.0)
    var compositionRate: Double? = nil         // 1.0% for manufacturers, 5.0% for restaurants

    mutating func generateNextInvoice() -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        if includeYearInInvoice, let lastYear = currentYear, year != lastYear {
            invoiceNumberCounter = 1
            currentYear = year
        }

        let number = invoiceNumberCounter
        invoiceNumberCounter += 1

        if includeYearInInvoice {
            return "\(invoicePrefix)-\(year)-\(String(format: "%04d", number))"
        } else {
            return "\(invoicePrefix)-\(String(format: "%06d", number))"
        }
    }
}

struct IncompleteSaleItem: Identifiable, Codable, Equatable {
    let id: UUID
    
    let transactionID: UUID
    let transactionItemID: UUID
    
    let itemName: String
    let quantity: Int
    let sellingPricePerUnit: Double
    
    var isCompleted: Bool
    var completedAt: Date?
    
    var unit: String?
    var costPricePerUnit: Double?
    var supplierName: String?
    var expiryDate: Date?
    
    let createdAt: Date
    
    var totalRevenue: Double {
        Double(quantity) * sellingPricePerUnit
    }
    
    var estimatedProfit: Double? {
        guard let cost = costPricePerUnit else { return nil }
        return Double(quantity) * (sellingPricePerUnit - cost)
    }
    
    var daysIncomplete: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }
}

struct IncompleteSaleSummary {
    let totalIncomplete: Int
    let oldestDate: Date?
    let totalRevenueUntracked: Double
    let itemNames: [String]
}

// MARK: - GST Data Structures

struct GSTBreakup: Codable {
    let totalTaxableValue: Double
    let totalCGST: Double
    let totalSGST: Double
    let totalIGST: Double
    let totalCess: Double
    var totalTax: Double { totalCGST + totalSGST + totalIGST + totalCess }
    var grandTotal: Double { totalTaxableValue + totalTax }
    let rateWiseSummary: [RateWiseEntry]

    enum CodingKeys: String, CodingKey {
        case totalTaxableValue, totalCGST, totalSGST, totalIGST, totalCess, rateWiseSummary
    }
}

struct RateWiseEntry: Codable {
    let gstRate: Double          // e.g., 18.0
    let taxableValue: Double
    let cgst: Double
    let sgst: Double
    let igst: Double
    let cess: Double
    var totalTax: Double { cgst + sgst + igst + cess }

    enum CodingKeys: String, CodingKey {
        case gstRate, taxableValue, cgst, sgst, igst, cess
    }
}

struct ItemTaxResult {
    let taxableValue: Double
    let cgst: Double
    let sgst: Double
    let igst: Double
    let cess: Double
    let totalTax: Double
    let totalWithTax: Double
}
