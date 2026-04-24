//  ManualSalesEntry

import Foundation

// MARK: - Database Protocol (storage abstraction)

protocol Database {
    // Item
    func getItem(id: UUID) throws -> Item?
    func getAllItems() throws -> [Item]
    func insertItem(_ item: Item) throws
    func updateItem(_ item: Item) throws
    func deleteItem(id: UUID) throws

    // Batches
    func getBatches(for itemID: UUID) throws -> [ItemBatch]
    func insertBatch(_ batch: ItemBatch) throws
    func updateBatch(_ batch: ItemBatch) throws

    // Transactions
    func insertTransaction(_ transaction: Transaction) throws
    func getTransactions() throws -> [Transaction]
    func insertTransactionItems(_ items: [TransactionItem]) throws
    func getTransactionItems(for transactionID: UUID) throws -> [TransactionItem]
    func getTransactionItem(id: UUID) throws -> TransactionItem?
    func updateTransactionItem(_ item: TransactionItem) throws
    
    // Sale item batches (FIFO tracking)
    func insertSaleItemBatches(_ batches: [SaleItemBatch]) throws
    func getSaleItemBatches(for transactionItemID: UUID) throws -> [SaleItemBatch]

    // Incomplete Sales
    func insertIncompleteSaleItem(_ item: IncompleteSaleItem) throws
    func getIncompleteSaleItem(id: UUID) throws -> IncompleteSaleItem?
    func getIncompleteSaleItems(completed: Bool?) throws -> [IncompleteSaleItem]
    func updateIncompleteSaleItem(_ item: IncompleteSaleItem) throws

    // Daily summary
    func getDailySummary(for date: Date) throws -> DailySummary?
    func upsertDailySummary(_ summary: DailySummary) throws
    
    // Settings
    func getSettings() throws -> AppSettings
    func updateSettings(_ settings: AppSettings) throws

    // Product Photos (for object detection fingerprinting)
    func insertProductPhoto(_ photo: ProductPhoto) throws
    func getProductPhotos(for itemID: UUID) throws -> [ProductPhoto]
    func deleteProductPhoto(id: UUID) throws
}

enum DataModelError: Error, LocalizedError {
    case invalidQuantity
    case itemNotFound
    case insufficientStock(available: Int, requested: Int)
    case incompleteSaleNotFound
    case incompleteSaleAlreadyCompleted
    case transactionItemNotFound
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidQuantity: return "Quantity must be greater than zero."
        case .itemNotFound: return "Item not found in database."
        case .insufficientStock(let available, let requested): return "Insufficient stock. Available: \(available), Requested: \(requested)."
        case .incompleteSaleNotFound: return "Incomplete sale record not found."
        case .incompleteSaleAlreadyCompleted: return "This incomplete sale has already been processed."
        case .transactionItemNotFound: return "Original transaction item not found."
        case .custom(let msg): return msg
        }
    }
}

// MARK: - DataModel (Domain Logic)

final class DataModel {
    
    public let db: Database
     let calendar = Calendar.current
    
    init(database: Database) {
        self.db = database
    }
    
    // MARK: - PURCHASE FLOW
    func addPurchase(
        itemID: UUID,
        quantity: Int,
        costPrice: Double,
        sellingPrice: Double,
        expiryDate: Date?,
        supplierName: String?,
        supplierGSTIN: String? = nil
    ) throws -> String {
        
        guard quantity > 0 else {
            throw DataModelError.invalidQuantity
        }
        
        let now = Date()
        let day = calendar.startOfDay(for: now)
        
        guard var item = try db.getItem(id: itemID) else {
            throw DataModelError.itemNotFound
        }
        
        var settings = try db.getSettings()
        let invoiceNumber = settings.generateNextInvoice()

        // GST calculation (if registered)
        var txItemHSN: String? = nil
        var txItemGSTRate: Double? = nil
        var txItemTaxable: Double? = nil
        var txItemCGST: Double? = nil
        var txItemSGST: Double? = nil
        var txItemIGST: Double? = nil
        var txItemCess: Double? = nil
        var txBuyerGSTIN: String? = nil
        var txIsInterState: Bool? = nil
        var txPlaceOfSupply: String? = nil
        var txPlaceOfSupplyCode: String? = nil
        var txTotalTaxable: Double? = nil
        var txTotalCGST: Double? = nil
        var txTotalSGST: Double? = nil
        var txTotalIGST: Double? = nil
        var txTotalCess: Double? = nil

        if settings.isGSTRegistered, let gstRate = item.gstRate {
            let isInterState = GSTEngine.isInterStateSupply(
                sellerStateCode: supplierGSTIN != nil ? String(supplierGSTIN!.prefix(2)) : nil,
                buyerStateCode: settings.businessStateCode
            )
            let taxResult = GSTEngine.calculateTax(
                price: costPrice,
                quantity: quantity,
                gstRate: gstRate,
                cessRate: item.cessRate ?? 0,
                isInterState: isInterState,
                pricesIncludeGST: settings.pricesIncludeGST
            )
            txItemHSN = item.hsnCode
            txItemGSTRate = gstRate
            txItemTaxable = taxResult.taxableValue
            txItemCGST = taxResult.cgst
            txItemSGST = taxResult.sgst
            txItemIGST = taxResult.igst
            txItemCess = taxResult.cess
            txBuyerGSTIN = supplierGSTIN
            txIsInterState = isInterState
            txPlaceOfSupply = settings.businessState
            txPlaceOfSupplyCode = settings.businessStateCode
            txTotalTaxable = taxResult.taxableValue
            txTotalCGST = taxResult.cgst
            txTotalSGST = taxResult.sgst
            txTotalIGST = taxResult.igst
            txTotalCess = taxResult.cess
        }
        
        let transaction = Transaction(
            id: UUID(),
            type: .purchase,
            date: now,
            invoiceNumber: invoiceNumber,
            customerName: nil,
            customerPhone: nil,
            supplierName: supplierName,
            totalAmount: Double(quantity) * costPrice,
            notes: nil,
            buyerGSTIN: txBuyerGSTIN,
            placeOfSupply: txPlaceOfSupply,
            placeOfSupplyCode: txPlaceOfSupplyCode,
            isInterState: txIsInterState,
            totalTaxableValue: txTotalTaxable,
            totalCGST: txTotalCGST,
            totalSGST: txTotalSGST,
            totalIGST: txTotalIGST,
            totalCess: txTotalCess,
            isReverseCharge: false
        )
        
        var txItem = TransactionItem(
            id: UUID(),
            transactionID: transaction.id,
            itemID: itemID,
            itemName: item.name,
            unit: item.unit,
            quantity: quantity,
            sellingPricePerUnit: sellingPrice,
            costPricePerUnit: costPrice,
            createdDate: now
        )
        txItem.hsnCode = txItemHSN
        txItem.gstRate = txItemGSTRate
        txItem.taxableValue = txItemTaxable
        txItem.cgstAmount = txItemCGST
        txItem.sgstAmount = txItemSGST
        txItem.igstAmount = txItemIGST
        txItem.cessAmount = txItemCess
        
        let batch = ItemBatch(
            id: UUID(),
            itemID: itemID,
            purchaseTransactionID: transaction.id,
            quantityPurchased: quantity,
            quantityRemaining: quantity,
            costPrice: costPrice,
            sellingPrice: sellingPrice,
            expiryDate: expiryDate,
            receivedDate: now
        )
        item.defaultCostPrice = costPrice
        item.defaultSellingPrice = sellingPrice
        item.defaultPriceUpdatedAt = now
        item.currentStock += quantity
        item.lastRestockDate = now
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems([txItem])
        try db.insertBatch(batch)
        try db.updateItem(item)
        try db.updateSettings(settings)
        
        let summary = try updatedDailySummary(
            date: day,
            purchaseAmount: Double(quantity) * costPrice
        )
        try db.upsertDailySummary(summary)
        return invoiceNumber
    }

    func addMultiItemPurchase(
        items: [(itemID: UUID, quantity: Int, costPrice: Double, sellingPrice: Double, expiryDate: Date?)],
        supplierName: String?,
        invoiceNumber: String? = nil,
        supplierGSTIN: String? = nil
    ) throws -> Transaction {
        
        guard !items.isEmpty else {
            throw DataModelError.custom("No items to purchase")
        }
        
        let now = Date()
        let day = calendar.startOfDay(for: now)
        var settings = try db.getSettings()
        
        let transactionID = UUID()
        let finalInvoiceNumber = invoiceNumber ?? settings.generateNextInvoice()
        
        var allTxItems: [TransactionItem] = []
        var allBatches: [ItemBatch] = []
        var totalPurchaseAmount: Double = 0
        var updatedItemsList: [Item] = []

        // GST accumulators (for ITC — Input Tax Credit)
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let isInterState = isGST ? GSTEngine.isInterStateSupply(
            sellerStateCode: supplierGSTIN != nil ? String(supplierGSTIN!.prefix(2)) : nil,
            buyerStateCode: settings.businessStateCode
        ) : false
        var billTotalTaxable: Double = 0
        var billTotalCGST: Double = 0
        var billTotalSGST: Double = 0
        var billTotalIGST: Double = 0
        var billTotalCess: Double = 0
        var hasGSTItems = false
        
        for purchaseItem in items {
            guard purchaseItem.quantity > 0 else { continue }
            
            guard var item = try db.getItem(id: purchaseItem.itemID) else {
                throw DataModelError.itemNotFound
            }
            
            let txItemID = UUID()
            var txItem = TransactionItem(
                id: txItemID,
                transactionID: transactionID,
                itemID: purchaseItem.itemID,
                itemName: item.name,
                unit: item.unit,
                quantity: purchaseItem.quantity,
                sellingPricePerUnit: purchaseItem.sellingPrice,
                costPricePerUnit: purchaseItem.costPrice,
                createdDate: now
            )

            // Per-item GST calculation (Regular scheme — for ITC)
            if isGST, let gstRate = item.gstRate {
                let taxResult = GSTEngine.calculateTax(
                    price: purchaseItem.costPrice,
                    quantity: purchaseItem.quantity,
                    gstRate: gstRate,
                    cessRate: item.cessRate ?? 0,
                    isInterState: isInterState,
                    pricesIncludeGST: settings.pricesIncludeGST
                )
                txItem.hsnCode = item.hsnCode
                txItem.gstRate = gstRate
                txItem.taxableValue = taxResult.taxableValue
                txItem.cgstAmount = taxResult.cgst
                txItem.sgstAmount = taxResult.sgst
                txItem.igstAmount = taxResult.igst
                txItem.cessAmount = taxResult.cess

                billTotalTaxable += taxResult.taxableValue
                billTotalCGST += taxResult.cgst
                billTotalSGST += taxResult.sgst
                billTotalIGST += taxResult.igst
                billTotalCess += taxResult.cess
                hasGSTItems = true
            }

            allTxItems.append(txItem)
            
            let batch = ItemBatch(
                id: UUID(),
                itemID: purchaseItem.itemID,
                purchaseTransactionID: transactionID,
                quantityPurchased: purchaseItem.quantity,
                quantityRemaining: purchaseItem.quantity,
                costPrice: purchaseItem.costPrice,
                sellingPrice: purchaseItem.sellingPrice,
                expiryDate: purchaseItem.expiryDate,
                receivedDate: now
            )
            allBatches.append(batch)
            
            item.defaultCostPrice = purchaseItem.costPrice
            item.defaultSellingPrice = purchaseItem.sellingPrice
            item.defaultPriceUpdatedAt = now
            item.currentStock += purchaseItem.quantity
            item.lastRestockDate = now
            updatedItemsList.append(item)
            
            totalPurchaseAmount += Double(purchaseItem.quantity) * purchaseItem.costPrice
        }
        
        let transaction = Transaction(
            id: transactionID,
            type: .purchase,
            date: now,
            invoiceNumber: finalInvoiceNumber,
            customerName: nil,
            customerPhone: nil,
            supplierName: supplierName,
            totalAmount: totalPurchaseAmount,
            notes: nil,
            buyerGSTIN: isGST ? supplierGSTIN : nil,
            placeOfSupply: isGST ? settings.businessState : nil,
            placeOfSupplyCode: isGST ? settings.businessStateCode : nil,
            isInterState: isGST ? isInterState : nil,
            totalTaxableValue: isGST && hasGSTItems ? billTotalTaxable : nil,
            totalCGST: isGST && hasGSTItems ? billTotalCGST : nil,
            totalSGST: isGST && hasGSTItems ? billTotalSGST : nil,
            totalIGST: isGST && hasGSTItems ? billTotalIGST : nil,
            totalCess: isGST && hasGSTItems ? billTotalCess : nil,
            isReverseCharge: false
        )
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems(allTxItems)
        for batch in allBatches {
            try db.insertBatch(batch)
        }
        for item in updatedItemsList {
            try db.updateItem(item)
        }
        
        if invoiceNumber == nil {
            try db.updateSettings(settings)
        }
        
        let summary = try updatedDailySummary(
            date: day,
            purchaseAmount: totalPurchaseAmount
        )
        try db.upsertDailySummary(summary)
        
        return transaction
    }

    
    

    struct BatchConsumptionResult {
        let consumptions: [(batch: ItemBatch, consumed: Int)]
        let updatedBatches: [ItemBatch]
        let totalCost: Double
        let totalRevenue: Double
    }

   
    func consumeBatchesFIFO(
        itemID: UUID,
        quantity: Int,
        sellingPrice: Double? = nil
    ) throws -> BatchConsumptionResult {
        var batches = try db.getBatches(for: itemID)
            .filter { $0.quantityRemaining > 0 }
            .sorted { b1, b2 in
                if let e1 = b1.expiryDate, let e2 = b2.expiryDate { return e1 < e2 }
                if b1.expiryDate == nil && b2.expiryDate == nil { return b1.receivedDate < b2.receivedDate }
                return b1.expiryDate != nil
            }

        let totalAvailable = batches.reduce(0) { $0 + $1.quantityRemaining }
        guard totalAvailable >= quantity else {
            throw DataModelError.insufficientStock(available: totalAvailable, requested: quantity)
        }

        var remaining = quantity
        var consumptions: [(batch: ItemBatch, consumed: Int)] = []
        var totalCost: Double = 0
        var totalRevenue: Double = 0

        for i in batches.indices where remaining > 0 {
            let consumeQty = min(batches[i].quantityRemaining, remaining)
            batches[i].quantityRemaining -= consumeQty
            consumptions.append((batch: batches[i], consumed: consumeQty))

            totalCost += Double(consumeQty) * batches[i].costPrice
            let price = sellingPrice ?? batches[i].sellingPrice
            totalRevenue += Double(consumeQty) * price
            remaining -= consumeQty
        }

        return BatchConsumptionResult(
            consumptions: consumptions,
            updatedBatches: batches,
            totalCost: totalCost,
            totalRevenue: totalRevenue
        )
    }

    // MARK: - SALE FLOW (FIFO/FEFO)
    func addSale(
        itemID: UUID,
        quantity: Int,
        customerName: String?,
        customerPhone: String?,
        buyerGSTIN: String? = nil,
        buyerStateCode: String? = nil
    ) throws {
        
        guard quantity > 0 else {
            throw DataModelError.invalidQuantity
        }
        
        let now = Date()
        let day = calendar.startOfDay(for: now)
        
        guard var item = try db.getItem(id: itemID) else {
            throw DataModelError.itemNotFound
        }
        
        var settings = try db.getSettings()
        
        var batches = try db.getBatches(for: itemID)
            .filter { $0.quantityRemaining > 0 }
            .sorted { batch1, batch2 in
                if let exp1 = batch1.expiryDate, let exp2 = batch2.expiryDate {
                    return exp1 < exp2
                }
                
                if batch1.expiryDate == nil && batch2.expiryDate == nil {
                    return batch1.receivedDate < batch2.receivedDate
                }
                
                return batch1.expiryDate != nil
            }
        
        let totalAvailable = batches.reduce(0) { $0 + $1.quantityRemaining }
        guard totalAvailable >= quantity else {
            throw DataModelError.insufficientStock(
                available: totalAvailable,
                requested: quantity
            )
        }
        
        var remainingToSell = quantity
        var batchConsumptions: [(batch: ItemBatch, consumed: Int)] = []
        var totalCost: Double = 0
        var totalRevenue: Double = 0
        
        for i in batches.indices where remainingToSell > 0 {
            var batch = batches[i]
            
            let consumeQty = min(batch.quantityRemaining, remainingToSell)
            
            batch.quantityRemaining -= consumeQty
            batches[i] = batch
            
            // Track consumption
            batchConsumptions.append((batch: batch, consumed: consumeQty))
            let batchRevenue = Double(consumeQty) * batch.sellingPrice
            let batchCost = Double(consumeQty) * batch.costPrice
            
            totalRevenue += batchRevenue
            totalCost += batchCost
            
            remainingToSell -= consumeQty
        }
        
        let avgSellingPrice = totalRevenue / Double(quantity)
        let avgCostPrice = totalCost / Double(quantity)
        let totalProfit = totalRevenue - totalCost
        
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let isInterState = isGST ? GSTEngine.isInterStateSupply(
            sellerStateCode: settings.businessStateCode,
            buyerStateCode: buyerStateCode ?? (buyerGSTIN != nil ? String(buyerGSTIN!.prefix(2)) : settings.businessStateCode)
        ) : false

        var txTotalTaxable: Double? = nil
        var txTotalCGST: Double? = nil
        var txTotalSGST: Double? = nil
        var txTotalIGST: Double? = nil
        var txTotalCess: Double? = nil
        
        var itemTaxable: Double? = nil
        var itemCGST: Double? = nil
        var itemSGST: Double? = nil
        var itemIGST: Double? = nil
        var itemCess: Double? = nil
        
        if isGST, let gstRate = item.gstRate {
            let taxResult = GSTEngine.calculateTax(
                price: avgSellingPrice,
                quantity: quantity,
                gstRate: gstRate,
                cessRate: item.cessRate ?? 0,
                isInterState: isInterState,
                pricesIncludeGST: settings.pricesIncludeGST
            )
            
            txTotalTaxable = taxResult.taxableValue
            txTotalCGST = taxResult.cgst
            txTotalSGST = taxResult.sgst
            txTotalIGST = taxResult.igst
            txTotalCess = taxResult.cess
            
            itemTaxable = taxResult.taxableValue
            itemCGST = taxResult.cgst
            itemSGST = taxResult.sgst
            itemIGST = taxResult.igst
            itemCess = taxResult.cess
        }

        let transactionID = UUID()
        let transaction = Transaction(
            id: transactionID,
            type: .sale,
            date: now,
            invoiceNumber: settings.generateNextInvoice(),
            customerName: customerName,
            customerPhone: customerPhone,
            supplierName: nil,
            totalAmount: totalRevenue,
            notes: nil,
            buyerGSTIN: isGST ? buyerGSTIN : nil,
            placeOfSupply: isGST ? (IndianStates.stateByCode(buyerStateCode ?? settings.businessStateCode ?? "")?.name ?? settings.businessState) : nil,
            placeOfSupplyCode: isGST ? (buyerStateCode ?? settings.businessStateCode) : nil,
            isInterState: isGST ? isInterState : nil,
            totalTaxableValue: txTotalTaxable,
            totalCGST: txTotalCGST,
            totalSGST: txTotalSGST,
            totalIGST: txTotalIGST,
            totalCess: txTotalCess,
            isReverseCharge: false
        )
        
        let txItemID = UUID()
        var txItem = TransactionItem(
            id: txItemID,
            transactionID: transactionID,
            itemID: itemID,
            itemName: item.name,
            unit: item.unit,
            quantity: quantity,
            sellingPricePerUnit: avgSellingPrice,
            costPricePerUnit: avgCostPrice,
            createdDate: now
        )
        
        if isGST {
            txItem.hsnCode = item.hsnCode
            txItem.gstRate = item.gstRate
            txItem.taxableValue = itemTaxable
            txItem.cgstAmount = itemCGST
            txItem.sgstAmount = itemSGST
            txItem.igstAmount = itemIGST
            txItem.cessAmount = itemCess
        }
        
        let saleItemBatches = batchConsumptions.map { consumption in
            SaleItemBatch(
                id: UUID(),
                transactionItemID: txItemID,
                batchID: consumption.batch.id,
                quantityConsumed: consumption.consumed,
                costPriceUsed: consumption.batch.costPrice,
                sellingPriceUsed: consumption.batch.sellingPrice,
                batchReceivedDate: consumption.batch.receivedDate,
                batchExpiryDate: consumption.batch.expiryDate
            )
        }
        
        let updatedBatches = try db.getBatches(for: itemID)
        let newStock = updatedBatches.reduce(0) { $0 + $1.quantityRemaining }
        item.currentStock = newStock - quantity  
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems([txItem])
        try db.insertSaleItemBatches(saleItemBatches)
        
        for batch in batches {
            try db.updateBatch(batch)
        }
        
        try db.updateItem(item)
        try db.updateSettings(settings) 
        
        let summary = try updatedDailySummary(
            date: day,
            revenue: totalRevenue,
            profit: totalProfit,
            itemsSold: quantity
        )
        try db.upsertDailySummary(summary)
        
        try updateSalesCountAndTiers(sold: [(itemID: itemID, quantity: quantity)])
    }
    
    func getExpiryAlerts() throws -> [ExpiryAlert] {
        let settings = try db.getSettings()
        let now = Date()
        
        let items = try getAllItems().filter { $0.isActive }
        
        var alerts: [ExpiryAlert] = []
        
        for item in items {
            let batches = try db.getBatches(for: item.id)
                .filter { $0.quantityRemaining > 0 }
            
            for batch in batches {
                guard let expiry = batch.expiryDate else { continue }
                
                let days = calendar.dateComponents([.day], from: now, to: expiry).day ?? 0
                
                let severity: ExpiryAlert.ExpirySeverity
                if days < 0 {
                    severity = .expired
                } else if days <= settings.expiryCriticalDays {
                    severity = .critical
                } else if days <= settings.expiryWarningDays {
                    severity = .warning
                } else if days <= settings.expiryNoticeDays {
                    severity = .notice
                } else {
                    continue  // Too far out
                }
                
                alerts.append(ExpiryAlert(
                    id: batch.id,
                    itemID: item.id,
                    itemName: item.name,
                    batchID: batch.id,
                    quantityRemaining: batch.quantityRemaining,
                    expiryDate: expiry,
                    daysUntilExpiry: days,
                    severity: severity
                ))
            }
        }
        
        return alerts.sorted { $0.severity < $1.severity }
    }
    func getLowStockAlerts() throws -> [LowStockAlert] {
        let items = try getAllItems()
            .filter { $0.isActive && $0.isLowStock }
        
        return items.map { item in
            LowStockAlert(
                id: item.id,
                itemID: item.id,
                itemName: item.name,
                currentStock: item.currentStock,
                threshold: item.lowStockThreshold,
                unit: item.unit
            )
        }
    }
    
     func updatedDailySummary(
        date: Date,
        revenue: Double = 0,
        profit: Double = 0,
        itemsSold: Int = 0,
        purchaseAmount: Double = 0
    ) throws -> DailySummary {
        let existing = try db.getDailySummary(for: date)
        
        return DailySummary(
            id: existing?.id ?? UUID(),
            date: date,
            totalRevenue: (existing?.totalRevenue ?? 0) + revenue,
            totalProfit: (existing?.totalProfit ?? 0) + profit,
            salesTransactionCount: (existing?.salesTransactionCount ?? 0) + (revenue > 0 ? 1 : 0),
            itemsSoldCount: (existing?.itemsSoldCount ?? 0) + itemsSold,
            totalPurchaseAmount: (existing?.totalPurchaseAmount ?? 0) + purchaseAmount,
            purchaseTransactionCount: (existing?.purchaseTransactionCount ?? 0) + (purchaseAmount > 0 ? 1 : 0)
        )
    }

     func getAllItems() throws -> [Item] {
        return try db.getAllItems()
    }
    func deleteItem(id: UUID) throws {
        try db.deleteItem(id: id)
    }
    
    func addMultiItemSale(
        items: [(itemID: UUID, quantity: Int, sellingPrice: Double)],
        customerName: String?,
        customerPhone: String?,
        discount: Double = 0,
        adjustment: Double = 0,
        invoiceNumber: String? = nil,
        buyerGSTIN: String? = nil,
        buyerStateCode: String? = nil
    ) throws -> Transaction {
        
        guard !items.isEmpty else {
            throw DataModelError.custom("No items to sell")
        }
        
        let now = Date()
        let day = calendar.startOfDay(for: now)
        var settings = try db.getSettings()
        
        let transactionID = UUID()
        var allTxItems: [TransactionItem] = []
        var allSaleItemBatches: [SaleItemBatch] = []
        var totalRevenue: Double = 0
        var totalCost: Double = 0
        var totalItemsSold: Int = 0
        var updatedBatchesList: [ItemBatch] = []
        var updatedItemsList: [Item] = []

        // GST accumulators
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let isInterState = isGST ? GSTEngine.isInterStateSupply(
            sellerStateCode: settings.businessStateCode,
            buyerStateCode: buyerStateCode ?? (buyerGSTIN != nil ? String(buyerGSTIN!.prefix(2)) : settings.businessStateCode)
        ) : false
        var gstItemResults: [(gstRate: Double, result: ItemTaxResult)] = []
        var billTotalTaxable: Double = 0
        var billTotalCGST: Double = 0
        var billTotalSGST: Double = 0
        var billTotalIGST: Double = 0
        var billTotalCess: Double = 0
        
        for saleItem in items {
            guard saleItem.quantity > 0 else { continue }
            
            guard var item = try db.getItem(id: saleItem.itemID) else {
                throw DataModelError.itemNotFound
            }
            
            var batches = try db.getBatches(for: saleItem.itemID)
                .filter { $0.quantityRemaining > 0 }
                .sorted { b1, b2 in
                    if let e1 = b1.expiryDate, let e2 = b2.expiryDate { return e1 < e2 }
                    if b1.expiryDate == nil && b2.expiryDate == nil { return b1.receivedDate < b2.receivedDate }
                    return b1.expiryDate != nil
                }
            
            let totalAvailable = batches.reduce(0) { $0 + $1.quantityRemaining }
            guard totalAvailable >= saleItem.quantity else {
                throw DataModelError.insufficientStock(available: totalAvailable, requested: saleItem.quantity)
            }
            
            var remaining = saleItem.quantity
            var batchConsumptions: [(batch: ItemBatch, consumed: Int)] = []
            var itemCost: Double = 0
            for i in batches.indices where remaining > 0 {
                let consumeQty = min(batches[i].quantityRemaining, remaining)
                batches[i].quantityRemaining -= consumeQty
                batchConsumptions.append((batch: batches[i], consumed: consumeQty))
                itemCost += Double(consumeQty) * batches[i].costPrice
                remaining -= consumeQty
            }
            let itemRevenue = Double(saleItem.quantity) * saleItem.sellingPrice
            let avgCostPrice = itemCost / Double(saleItem.quantity)
            let txItemID = UUID()
            var txItem = TransactionItem(
                id: txItemID,
                transactionID: transactionID,
                itemID: saleItem.itemID,
                itemName: item.name,
                unit: item.unit,
                quantity: saleItem.quantity,
                sellingPricePerUnit: saleItem.sellingPrice,
                costPricePerUnit: avgCostPrice,
                createdDate: now
            )

            // Per-item GST calculation (Regular scheme only)
            if isGST, let gstRate = item.gstRate {
                let taxResult = GSTEngine.calculateTax(
                    price: saleItem.sellingPrice,
                    quantity: saleItem.quantity,
                    gstRate: gstRate,
                    cessRate: item.cessRate ?? 0,
                    isInterState: isInterState,
                    pricesIncludeGST: settings.pricesIncludeGST
                )
                txItem.hsnCode = item.hsnCode
                txItem.gstRate = gstRate
                txItem.taxableValue = taxResult.taxableValue
                txItem.cgstAmount = taxResult.cgst
                txItem.sgstAmount = taxResult.sgst
                txItem.igstAmount = taxResult.igst
                txItem.cessAmount = taxResult.cess

                gstItemResults.append((gstRate: gstRate, result: taxResult))
                billTotalTaxable += taxResult.taxableValue
                billTotalCGST += taxResult.cgst
                billTotalSGST += taxResult.sgst
                billTotalIGST += taxResult.igst
                billTotalCess += taxResult.cess
            }

            allTxItems.append(txItem)
            
            for consumption in batchConsumptions {
                allSaleItemBatches.append(SaleItemBatch(
                    id: UUID(),
                    transactionItemID: txItemID,
                    batchID: consumption.batch.id,
                    quantityConsumed: consumption.consumed,
                    costPriceUsed: consumption.batch.costPrice,
                    sellingPriceUsed: saleItem.sellingPrice,
                    batchReceivedDate: consumption.batch.receivedDate,
                    batchExpiryDate: consumption.batch.expiryDate
                ))
            }
            
            item.currentStock -= saleItem.quantity
            updatedItemsList.append(item)
            updatedBatchesList.append(contentsOf: batches)
            totalRevenue += itemRevenue
            totalCost += itemCost
            totalItemsSold += saleItem.quantity
        }
        let grandTotal = totalRevenue - discount + adjustment
        let totalProfit = totalRevenue - totalCost
        
        let transaction = Transaction(
            id: transactionID,
            type: .sale,
            date: now,
            invoiceNumber: invoiceNumber ?? settings.generateNextInvoice(),
            customerName: customerName,
            customerPhone: customerPhone,
            supplierName: nil,
            totalAmount: grandTotal,
            notes: nil,
            buyerGSTIN: isGST ? buyerGSTIN : nil,
            placeOfSupply: isGST ? (IndianStates.stateByCode(buyerStateCode ?? settings.businessStateCode ?? "")?.name ?? settings.businessState) : nil,
            placeOfSupplyCode: isGST ? (buyerStateCode ?? settings.businessStateCode) : nil,
            isInterState: isGST ? isInterState : nil,
            totalTaxableValue: isGST && !gstItemResults.isEmpty ? billTotalTaxable : nil,
            totalCGST: isGST && !gstItemResults.isEmpty ? billTotalCGST : nil,
            totalSGST: isGST && !gstItemResults.isEmpty ? billTotalSGST : nil,
            totalIGST: isGST && !gstItemResults.isEmpty ? billTotalIGST : nil,
            totalCess: isGST && !gstItemResults.isEmpty ? billTotalCess : nil,
            isReverseCharge: false
        )
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems(allTxItems)
        try db.insertSaleItemBatches(allSaleItemBatches)
        for batch in updatedBatchesList {
            try db.updateBatch(batch)
        }
        for item in updatedItemsList {
            try db.updateItem(item)
        }
        if invoiceNumber == nil {
            try db.updateSettings(settings)
        }
        let summary = try updatedDailySummary(
            date: day,
            revenue: grandTotal,
            profit: totalProfit,
            itemsSold: totalItemsSold
        )
        try db.upsertDailySummary(summary)
        let sold = items.map { (itemID: $0.itemID, quantity: $0.quantity) }
        try updateSalesCountAndTiers(sold: sold)
        
        return transaction
    }
     func updateSalesCountAndTiers(sold: [(itemID: UUID, quantity: Int)]) throws {
        for (id, qty) in sold {
            guard var item = try db.getItem(id: id) else { continue }
            item.salesCount = (item.salesCount ?? 0) + qty
            try db.updateItem(item)
        }
        var all = try db.getAllItems()
        all.sort { ($0.salesCount ?? 0) > ($1.salesCount ?? 0) }
        let n = all.count
        let t1 = max(1, n / 10)
        let t2 = max(0, n * 4 / 10)
        for (i, var item) in all.enumerated() {
            if i < t1 { item.salesTier = 1 }
            else if i < t1 + t2 { item.salesTier = 2 }
            else { item.salesTier = 3 }
            try db.updateItem(item)
        }
    }
    func recordSaleWithoutStockCheck(
        items: [(itemID: UUID, quantity: Int, sellingPrice: Double)],
        customerName: String?,
        customerPhone: String?,
        discount: Double = 0,
        adjustment: Double = 0,
        invoiceNumber: String? = nil,
        buyerGSTIN: String? = nil,
        buyerStateCode: String? = nil
    ) throws -> Transaction {
        guard !items.isEmpty else {
            throw DataModelError.custom("No items to sell")
        }
        let now = Date()
        let day = calendar.startOfDay(for: now)
        var settings = try db.getSettings()
        let transactionID = UUID()
        var allTxItems: [TransactionItem] = []
        var totalRevenue: Double = 0
        var totalItemsSold: Int = 0

        // GST accumulators
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let isInterState = isGST ? GSTEngine.isInterStateSupply(
            sellerStateCode: settings.businessStateCode,
            buyerStateCode: buyerStateCode ?? (buyerGSTIN != nil ? String(buyerGSTIN!.prefix(2)) : settings.businessStateCode)
        ) : false
        var gstItemResults: [(gstRate: Double, result: ItemTaxResult)] = []
        var billTotalTaxable: Double = 0
        var billTotalCGST: Double = 0
        var billTotalSGST: Double = 0
        var billTotalIGST: Double = 0
        var billTotalCess: Double = 0

        for saleItem in items {
            guard saleItem.quantity > 0 else { continue }
            let itemOpt = try db.getItem(id: saleItem.itemID)
            let itemName = itemOpt?.name ?? "Unknown"
            let itemUnit = itemOpt?.unit ?? "piece"
            var txItem = TransactionItem(
                id: UUID(),
                transactionID: transactionID,
                itemID: saleItem.itemID,
                itemName: itemName,
                unit: itemUnit,
                quantity: saleItem.quantity,
                sellingPricePerUnit: saleItem.sellingPrice,
                costPricePerUnit: nil, // Unknown — no batch consumed
                createdDate: now
            )

            // Per-item GST calculation (Regular scheme only)
            if isGST, let item = itemOpt, let gstRate = item.gstRate {
                let taxResult = GSTEngine.calculateTax(
                    price: saleItem.sellingPrice,
                    quantity: saleItem.quantity,
                    gstRate: gstRate,
                    cessRate: item.cessRate ?? 0,
                    isInterState: isInterState,
                    pricesIncludeGST: settings.pricesIncludeGST
                )
                txItem.hsnCode = item.hsnCode
                txItem.gstRate = gstRate
                txItem.taxableValue = taxResult.taxableValue
                txItem.cgstAmount = taxResult.cgst
                txItem.sgstAmount = taxResult.sgst
                txItem.igstAmount = taxResult.igst
                txItem.cessAmount = taxResult.cess

                gstItemResults.append((gstRate: gstRate, result: taxResult))
                billTotalTaxable += taxResult.taxableValue
                billTotalCGST += taxResult.cgst
                billTotalSGST += taxResult.sgst
                billTotalIGST += taxResult.igst
                billTotalCess += taxResult.cess
            }

            allTxItems.append(txItem)
            totalRevenue += Double(saleItem.quantity) * saleItem.sellingPrice
            totalItemsSold += saleItem.quantity
        }
        let grandTotal = totalRevenue - discount + adjustment
        let transaction = Transaction(
            id: transactionID,
            type: .sale,
            date: now,
            invoiceNumber: invoiceNumber ?? settings.generateNextInvoice(),
            customerName: customerName,
            customerPhone: customerPhone,
            supplierName: nil,
            totalAmount: grandTotal,
            notes: "Recorded with insufficient stock",
            buyerGSTIN: isGST ? buyerGSTIN : nil,
            placeOfSupply: isGST ? (IndianStates.stateByCode(buyerStateCode ?? settings.businessStateCode ?? "")?.name ?? settings.businessState) : nil,
            placeOfSupplyCode: isGST ? (buyerStateCode ?? settings.businessStateCode) : nil,
            isInterState: isGST ? isInterState : nil,
            totalTaxableValue: isGST && !gstItemResults.isEmpty ? billTotalTaxable : nil,
            totalCGST: isGST && !gstItemResults.isEmpty ? billTotalCGST : nil,
            totalSGST: isGST && !gstItemResults.isEmpty ? billTotalSGST : nil,
            totalIGST: isGST && !gstItemResults.isEmpty ? billTotalIGST : nil,
            totalCess: isGST && !gstItemResults.isEmpty ? billTotalCess : nil,
            isReverseCharge: false
        )
        try db.insertTransaction(transaction)
        try db.insertTransactionItems(allTxItems)
        if invoiceNumber == nil {
            try db.updateSettings(settings)
        }
        let summary = try updatedDailySummary(
            date: day, revenue: grandTotal, profit: 0, itemsSold: totalItemsSold
        )
        try db.upsertDailySummary(summary)

        return transaction
    }
    
    // MARK: - DASHBOARD & TAB STATS

    struct TodayStats {
        var revenue: Double = 0
        var profit: Double = 0
        var purchaseTotal: Double = 0
        var saleCount: Int = 0
        var itemsSold: Int = 0
        var itemsPurchased: Set<UUID> = []
    }

    func getTodayStats() -> TodayStats {
        guard let transactions = try? db.getTransactions() else { return TodayStats() }
        let today = calendar.startOfDay(for: Date())
        var stats = TodayStats()

        for tx in transactions {
            guard calendar.startOfDay(for: tx.date) == today else { continue }
            switch tx.type {
            case .sale:
                stats.revenue += tx.totalAmount
                stats.saleCount += 1
                let items = (try? db.getTransactionItems(for: tx.id)) ?? []
                for item in items {
                    stats.profit += Double(item.quantity) * ((item.sellingPricePerUnit ?? 0) - (item.costPricePerUnit ?? 0))
                    stats.itemsSold += item.quantity
                }
            case .purchase:
                stats.purchaseTotal += tx.totalAmount
                let items = (try? db.getTransactionItems(for: tx.id)) ?? []
                for item in items {
                    stats.itemsPurchased.insert(item.itemID)
                }
            }
        }
        return stats
    }

    func getFinancialYearRevenue() -> Double {
        guard let transactions = try? db.getTransactions() else { return 0 }
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let startYear = (month >= 4) ? year : year - 1
        
        var components = DateComponents()
        components.year = startYear
        components.month = 4
        components.day = 1
        guard let startDate = calendar.date(from: components) else { return 0 }
        
        return transactions.filter { $0.type == .sale && $0.date >= startDate && $0.date <= now }
                           .reduce(0) { $0 + $1.totalAmount }
    }

    func getFinancialYearInvestment() -> Double {
        // Investment is usually "total value currently on hand", which is already what getTotalInvestment() calculates.
        // However, if we want total spend in FY:
        guard let transactions = try? db.getTransactions() else { return 0 }
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let startYear = (month >= 4) ? year : year - 1
        
        var components = DateComponents()
        components.year = startYear
        components.month = 4
        components.day = 1
        guard let startDate = calendar.date(from: components) else { return 0 }
        
        return transactions.filter { $0.type == .purchase && $0.date >= startDate && $0.date <= now }
                           .reduce(0) { $0 + $1.totalAmount }
    }

    // Backward-compatible thin wrappers
    func getTodayRevenue() -> Double { getTodayStats().revenue }
    func getTodayProfit() -> Double { getTodayStats().profit }
    func getTodayPurchaseTotal() -> Double { getTodayStats().purchaseTotal }
    func getTodayItemsPurchasedCount() -> Int { getTodayStats().itemsPurchased.count }
    func getTodaySaleCount() -> Int { getTodayStats().saleCount }
    func getTodayItemsSoldCount() -> Int { getTodayStats().itemsSold }
    func getTotalInvestment() -> Double {
        guard let items = try? db.getAllItems() else { return 0 }
        var total: Double = 0
        for item in items {
            if let batches = try? db.getBatches(for: item.id) {
                for batch in batches where batch.quantityRemaining > 0 {
                    total += Double(batch.quantityRemaining) * batch.costPrice
                }
            }
        }
        return total
    }
    func generateInvoiceNumber(for type: TransactionType = .sale) -> String {
        let prefix = type == .sale ? "S" : "P"
        
        let df = DateFormatter()
        df.dateFormat = "ddMMyy"
        let dateKey = df.string(from: Date())
        
        // Count today's existing transactions of this type to determine sequence
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let allTx = (try? db.getTransactions()) ?? []
        let todayCount = allTx.filter { tx in
            tx.type == type && calendar.startOfDay(for: tx.date) == startOfDay
        }.count
        
        let sequence = todayCount + 1
        return "\(prefix)\(dateKey)-\(sequence)"
    }
    func getRecentTransactions(limit: Int = 10, type: TransactionType? = nil) -> [(transaction: Transaction, itemsSummary: String)] {
        guard let transactions = try? db.getTransactions() else { return [] }
        
        let filtered: [Transaction]
        if let type = type {
            filtered = transactions.filter { $0.type == type }
        } else {
            filtered = transactions
        }
        
        let limited = Array(filtered.sorted { $0.date > $1.date }.prefix(limit))
        
        return limited.map { tx in
            let items = (try? db.getTransactionItems(for: tx.id)) ?? []
            let summary: String
            if items.isEmpty {
                summary = tx.notes ?? ""
            } else if items.count == 1 {
                let item = items[0]
                summary = "\(item.itemName) × \(item.quantity)"
            } else {
                let first = items[0]
                summary = "\(first.itemName) × \(first.quantity) + \(items.count - 1) more"
            }
            return (transaction: tx, itemsSummary: summary)
        }
    }
}

extension DataModel {
    
    // MARK: - QUICK SALE (Without Full Item Setup)
    func addQuickSale(
        itemName: String,
        quantity: Int,
        sellingPrice: Double,
        customerName: String?,
        customerPhone: String?
    ) throws -> (transaction: Transaction, incompleteSaleItem: IncompleteSaleItem) {
        
        guard quantity > 0, sellingPrice >= 0 else {
            throw DataModelError.invalidQuantity
        }
        
        let now = Date()
        let day = calendar.startOfDay(for: now)
        
        var settings = try db.getSettings()
        
        let transactionID = UUID()
        let transaction = Transaction(
            id: transactionID,
            type: .sale,
            date: now,
            invoiceNumber: settings.generateNextInvoice(),
            customerName: customerName,
            customerPhone: customerPhone,
            supplierName: nil,
            totalAmount: Double(quantity) * sellingPrice,
            notes: "⚠️ Quick sale - item details incomplete"
        )
        
        let txItemID = UUID()
        let placeholderItemID = UUID()
        
        let txItem = TransactionItem(
            id: txItemID,
            transactionID: transactionID,
            itemID: placeholderItemID,
            itemName: itemName,
            unit: "piece",  // Default
            quantity: quantity,
            sellingPricePerUnit: sellingPrice,
            costPricePerUnit: nil,  // Unknown
            createdDate: now
        )
        
        let incompleteSaleItem = IncompleteSaleItem(
            id: UUID(),
            transactionID: transactionID,
            transactionItemID: txItemID,
            itemName: itemName,
            quantity: quantity,
            sellingPricePerUnit: sellingPrice,
            isCompleted: false,
            completedAt: nil,
            unit: nil,
            costPricePerUnit: nil,
            supplierName: nil,
            expiryDate: nil,
            createdAt: now
        )
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems([txItem])
        try db.insertIncompleteSaleItem(incompleteSaleItem)
        try db.updateSettings(settings)
        
        let summary = try updatedDailySummary(
            date: day,
            revenue: Double(quantity) * sellingPrice,
            profit: 0,  // Can't calculate without cost
            itemsSold: quantity
        )
        try db.upsertDailySummary(summary)
        
        return (transaction, incompleteSaleItem)
    }
    
    // MARK: - COMPLETE INCOMPLETE SALE
    func completeIncompleteSale(
        incompleteSaleItemID: UUID,
        unit: String,
        costPrice: Double,
        defaultSellingPrice: Double?,
        lowStockThreshold: Int,
        supplierName: String?,
        expiryDate: Date?
    ) throws {
        
        guard var incompleteSale = try db.getIncompleteSaleItem(id: incompleteSaleItemID) else {
            throw DataModelError.incompleteSaleNotFound
        }
        
        guard !incompleteSale.isCompleted else {
            throw DataModelError.incompleteSaleAlreadyCompleted
        }
        
        let now = Date()
        
        let itemID = UUID()
        let item = Item(
            id: itemID,
            name: incompleteSale.itemName,
            unit: unit,
            defaultCostPrice: costPrice,
            defaultSellingPrice: defaultSellingPrice ?? incompleteSale.sellingPricePerUnit,
            defaultPriceUpdatedAt: now,
            lowStockThreshold: lowStockThreshold,
            currentStock: 0,  // Will be negative after retroactive sale
            createdDate: now,
            lastRestockDate: nil,
            isActive: true
        )
        
        // This batch will have negative stock initially
        let purchaseTxID = UUID()
        let virtualPurchase = Transaction(
            id: purchaseTxID,
            type: .purchase,
            date: incompleteSale.createdAt,  // Backdated to sale date
            invoiceNumber: "RETRO-\(UUID().uuidString.prefix(8))",
            customerName: nil,
            customerPhone: nil,
            supplierName: supplierName,
            totalAmount: Double(incompleteSale.quantity) * costPrice,
            notes: "Retroactive purchase for incomplete sale #\(incompleteSale.id)"
        )
        
        let purchaseTxItem = TransactionItem(
            id: UUID(),
            transactionID: purchaseTxID,
            itemID: itemID,
            itemName: incompleteSale.itemName,
            unit: unit,
            quantity: incompleteSale.quantity,
            sellingPricePerUnit: incompleteSale.sellingPricePerUnit,
            costPricePerUnit: costPrice,
            createdDate: incompleteSale.createdAt
        )
        
        let batchID = UUID()
        let batch = ItemBatch(
            id: batchID,
            itemID: itemID,
            purchaseTransactionID: purchaseTxID,
            quantityPurchased: incompleteSale.quantity,
            quantityRemaining: 0,  // Already sold
            costPrice: costPrice,
            sellingPrice: incompleteSale.sellingPricePerUnit,
            expiryDate: expiryDate,
            receivedDate: incompleteSale.createdAt
        )
        
        guard var originalTxItem = try db.getTransactionItem(id: incompleteSale.transactionItemID) else {
            throw DataModelError.transactionItemNotFound
        }
        
        originalTxItem = TransactionItem(
            id: originalTxItem.id,
            transactionID: originalTxItem.transactionID,
            itemID: itemID,  // Update to real item ID
            itemName: originalTxItem.itemName,
            unit: unit,
            quantity: originalTxItem.quantity,
            sellingPricePerUnit: originalTxItem.sellingPricePerUnit,
            costPricePerUnit: costPrice,  
            createdDate: originalTxItem.createdDate
        )
        
        let saleItemBatch = SaleItemBatch(
            id: UUID(),
            transactionItemID: originalTxItem.id,
            batchID: batchID,
            quantityConsumed: incompleteSale.quantity,
            costPriceUsed: costPrice,
            sellingPriceUsed: incompleteSale.sellingPricePerUnit,
            batchReceivedDate: incompleteSale.createdAt,
            batchExpiryDate: expiryDate
        )
        
        incompleteSale.isCompleted = true
        incompleteSale.completedAt = now
        incompleteSale.unit = unit
        incompleteSale.costPricePerUnit = costPrice
        incompleteSale.supplierName = supplierName
        incompleteSale.expiryDate = expiryDate
        
        let saleDate = calendar.startOfDay(for: incompleteSale.createdAt)
        let profit = Double(incompleteSale.quantity) * (incompleteSale.sellingPricePerUnit - costPrice)
        
        let summary = try updatedDailySummary(
            date: saleDate,
            revenue: 0,  // Already counted
            profit: profit,  // Now we can add profit
            itemsSold: 0  // Already counted
        )
        
        try db.insertItem(item)
        try db.insertTransaction(virtualPurchase)
        try db.insertTransactionItems([purchaseTxItem])
        try db.insertBatch(batch)
        try db.updateTransactionItem(originalTxItem)
        try db.insertSaleItemBatches([saleItemBatch])
        try db.updateIncompleteSaleItem(incompleteSale)
        try db.upsertDailySummary(summary)
    }
    
    // MARK: - GET INCOMPLETE SALES
    func getIncompleteSales() throws -> [IncompleteSaleItem] {
        return try db.getIncompleteSaleItems(completed: false)
            .sorted { $0.createdAt > $1.createdAt }
    }
    func getIncompleteSalesSummary() throws -> IncompleteSaleSummary {
        let incomplete = try getIncompleteSales()
        
        return IncompleteSaleSummary(
            totalIncomplete: incomplete.count,
            oldestDate: incomplete.last?.createdAt,
            totalRevenueUntracked: incomplete.reduce(0) { $0 + $1.totalRevenue },
            itemNames: Array(incomplete.prefix(3).map { $0.itemName })
        )
    }
    func getPurchaseDatesFromBatches(for itemID: UUID) throws -> [Date] {
        let batches = try db.getBatches(for: itemID)
        
        return batches
            .map { $0.receivedDate }
            .sorted()
    }
}
