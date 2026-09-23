import Foundation

// MARK: - ITEM TYPE
enum ItemType: String, Codable, CaseIterable {
    case goods = "goods"
    case services = "services"

    var displayName: String {
        switch self {
        case .goods:    return "Goods"
        case .services: return "Service"
        }
    }
}

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

   
    var lowStockThreshold: Double
    var currentStock: Double
 
    let createdDate: Date
    var lastRestockDate: Date?
    var isActive: Bool
    var salesCount: Double? = nil
    var salesTier: Int? = nil

   
    var alternateUnitName: String? = nil
    var alternateUnitFactor: Double? = nil

   
    var hsnCode: String? = nil       
    var gstRate: Double? = nil    
    var cessRate: Double? = nil     

   
    var itemType: ItemType = .goods

    var effectiveSalesTier: Int { salesTier ?? 2 }
    var effectiveSalesCount: Int { Int((salesCount ?? 0).rounded()) }

    var isService: Bool { itemType == .services }

    var isLowStock: Bool {
        guard !isService else { return false }
        return currentStock <= lowStockThreshold
    }
}


struct ItemBatch: Identifiable, Codable, Equatable {
    let id: UUID
    let itemID: UUID                    // FK → Item.id
    let purchaseTransactionID: UUID     // FK → Transaction.id

    let quantityPurchased: Double
    var quantityRemaining: Double

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
    
    let quantityConsumed: Double
    let costPriceUsed: Double
    let sellingPriceUsed: Double
    
    let batchReceivedDate: Date
    let batchExpiryDate: Date?
    
   
    var profit: Double {
        quantityConsumed * (sellingPriceUsed - costPriceUsed)
    }
    
    var revenue: Double {
        quantityConsumed * sellingPriceUsed
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

 
    var buyerGSTIN: String? = nil
    var placeOfSupply: String? = nil         
    var placeOfSupplyCode: String? = nil   
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
    let quantity: Double
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
    
    var itemType: ItemType? = nil

    var totalRevenue: Double {
        guard let price = sellingPricePerUnit else { return 0 }
        return Money.line(quantity: quantity, rate: price)
    }
    
    var totalCost: Double {
        guard let price = costPricePerUnit else { return 0 }
        return Money.line(quantity: quantity, rate: price)
    }
    
    var profit: Double {
        guard let sell = sellingPricePerUnit, let cost = costPricePerUnit else { return 0 }
        return Money.round2(totalRevenue - totalCost)
    }
    
    var profitMargin: Double {
        guard let sell = sellingPricePerUnit, sell > 0, totalRevenue > 0 else { return 0 }
        return (profit / totalRevenue) * 100
    }
}

struct DailySummary: Identifiable, Codable {
    let id: UUID
    let date: Date

    let totalRevenue: Double
    let totalProfit: Double
    let salesTransactionCount: Int
    let itemsSoldCount: Double

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
    let quantitySold: Double
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
    let quantitySold: Double
    let profitPerUnit: Double
}

struct TodaySnapshot {
    let date: Date
    let revenue: Double
    let profit: Double
    let profitMargin: Double
    let itemsSold: Double
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
    let quantityRemaining: Double
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
    let currentStock: Double
    let threshold: Double
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
    
    var expiryNoticeDays: Int       
    var expiryWarningDays: Int      
    var expiryCriticalDays: Int     

    // GST configuration fields
    var isGSTRegistered: Bool = false          
    var gstScheme: String? = nil              
    var businessState: String? = nil           
    var businessStateCode: String? = nil       
    var pricesIncludeGST: Bool = true         
    var defaultGSTRate: Double? = nil         
    var compositionRate: Double? = nil         

    
    var upiVPA: String? = nil
    var upiQRImageData: Data? = nil

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
    let quantity: Double
    let sellingPricePerUnit: Double
    
    var isCompleted: Bool
    var completedAt: Date?
    
    var unit: String?
    var costPricePerUnit: Double?
    var supplierName: String?
    var expiryDate: Date?
    
    let createdAt: Date
    
    var itemType: ItemType? = nil
    
    var totalRevenue: Double {
        Money.line(quantity: quantity, rate: sellingPricePerUnit)
    }
    
    var estimatedProfit: Double? {
        guard let cost = costPricePerUnit else { return nil }
        return Money.round2(totalRevenue - Money.line(quantity: quantity, rate: cost))
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
    var totalTax: Double { Money.round2(totalCGST + totalSGST + totalIGST + totalCess) }
    var grandTotal: Double { Money.round2(totalTaxableValue + totalTax) }
    let rateWiseSummary: [RateWiseEntry]

    enum CodingKeys: String, CodingKey {
        case totalTaxableValue, totalCGST, totalSGST, totalIGST, totalCess, rateWiseSummary
    }
}

struct RateWiseEntry: Codable {
    let gstRate: Double         
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
