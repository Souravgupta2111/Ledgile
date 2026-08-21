//  ManualSalesEntry

import Foundation



nonisolated protocol Database {
    // Item
    func getItem(id: UUID) throws -> Item?
    func getAllItems() throws -> [Item]
    func insertItem(_ item: Item) throws
    func updateItem(_ item: Item) throws
    func deleteItem(id: UUID) throws
    func retroactivelyUpdateCostPrice(for itemID: UUID, newCP: Double) throws

    func getBatches(for itemID: UUID) throws -> [ItemBatch]
    func insertBatch(_ batch: ItemBatch) throws
    func updateBatch(_ batch: ItemBatch) throws

    // Transactions
    func insertTransaction(_ transaction: Transaction) throws
    func getTransaction(id: UUID) throws -> Transaction?
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

    func performWrite(_ body: () throws -> Void) throws
    func decrementBatchQuantity(id: UUID, by quantity: Double) throws

    // Product Photos (for object detection fingerprinting)
    func insertProductPhoto(_ photo: ProductPhoto) throws
    func getProductPhotos(for itemID: UUID) throws -> [ProductPhoto]
    func deleteProductPhoto(id: UUID) throws
}

enum DataModelError: Error, LocalizedError {
    case invalidQuantity
    case itemNotFound
    case insufficientStock(available: Double, requested: Double)
    case insufficientStockMulti(items: [String])
    case incompleteSaleNotFound
    case incompleteSaleAlreadyCompleted
    case transactionItemNotFound
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidQuantity: return "Quantity must be greater than zero."
        case .itemNotFound: return "Item not found in database."
        case .insufficientStock(let available, let requested): return "Insufficient stock. Available: \(available), Requested: \(requested)."
        case .insufficientStockMulti(let items): return "Sale recorded, but stock is insufficient for: \(items.joined(separator: ", ")). Please purchase more inventory."
        case .incompleteSaleNotFound: return "Incomplete sale record not found."
        case .incompleteSaleAlreadyCompleted: return "This incomplete sale has already been processed."
        case .transactionItemNotFound: return "Original transaction item not found."
        case .custom(let msg): return msg
        }
    }
}

// MARK: - DataModel (Domain Logic)

nonisolated final class DataModel: @unchecked Sendable {
    
    public let db: Database
     let calendar = Calendar.current
    
    init(database: Database) {
        self.db = database
    }

    /// Money only. Do not use for kg/litre quantity.
    private func rupees(_ value: Double) -> Double { Money.round2(value) }

    private func lineRupees(quantity: Double, rate: Double) -> Double {
        Money.line(quantity: quantity, rate: rate)
    }

    private func resolveBuyerPlaceOfSupply(
        isGST: Bool,
        explicit: String?,
        gstin: String?,
        shopStateCode: String?
    ) throws -> String? {
        let fromGSTINOrExplicit = GSTEngine.buyerStateCode(
            explicit: explicit,
            gstin: gstin,
            shopStateCode: nil
        )
        if isGST, gstin != nil, fromGSTINOrExplicit == nil {
            throw DataModelError.custom("Place of supply is required for invoices with a buyer GSTIN.")
        }
        if let fromGSTINOrExplicit { return fromGSTINOrExplicit }
        _ = shopStateCode
        return nil
    }

    private func gstInterStateOrThrow(isGST: Bool, sellerCode: String?, buyerCode: String?) throws -> Bool {
        guard isGST else { return false }
        guard let known = GSTEngine.isInterStateSupply(sellerStateCode: sellerCode, buyerStateCode: buyerCode) else {
            throw DataModelError.custom("Place of supply is required for GST invoices. Unknown place of supply is not treated as intra-state.")
        }
        return known
    }
    
    // MARK: - PURCHASE FLOW
    func addPurchase(
        itemID: UUID,
        quantity: Double,
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

        if settings.isGSTRegistered, let gstRate = item.gstRate,
           let isInterState = GSTEngine.isInterStateSupply(
            sellerStateCode: supplierGSTIN.map { String($0.prefix(2)) },
            buyerStateCode: settings.businessStateCode
           ) {
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
            totalAmount: lineRupees(quantity: quantity, rate: costPrice),
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
        
        item.defaultCostPrice = costPrice
        item.defaultSellingPrice = sellingPrice
        item.defaultPriceUpdatedAt = now
        
        try db.insertTransaction(transaction)
        try db.insertTransactionItems([txItem])

        // Services: no batch or stock tracking
        if !item.isService {
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
            try db.insertBatch(batch)
            item.currentStock += quantity
            item.lastRestockDate = now
        }

        try db.updateItem(item)
        try db.updateSettings(settings)
        
        let summary = try updatedDailySummary(
            date: day,
            purchaseAmount: lineRupees(quantity: quantity, rate: costPrice)
        )
        try db.upsertDailySummary(summary)
        return invoiceNumber
    }

    func addMultiItemPurchase(
        items: [(itemID: UUID, quantity: Double, costPrice: Double, sellingPrice: Double, expiryDate: Date?)],
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
            sellerStateCode: supplierGSTIN.map { String($0.prefix(2)) },
            buyerStateCode: settings.businessStateCode
        ) : false
        let applyPurchaseGST = isGST && isInterState != nil
        var billTotalTaxable: Double = 0
        var billTotalCGST: Double = 0
        var billTotalSGST: Double = 0
        var billTotalIGST: Double = 0
        var billTotalCess: Double = 0
        var hasGSTItems = false
        
        var inMemoryItems: [UUID: Item] = [:]
        
        for purchaseItem in items {
            guard purchaseItem.quantity > 0 else { continue }
            
            var item: Item
            if let cached = inMemoryItems[purchaseItem.itemID] {
                item = cached
            } else if let dbItem = try db.getItem(id: purchaseItem.itemID) {
                item = dbItem
            } else {
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
            if applyPurchaseGST, let gstRate = item.gstRate, let interState = isInterState {
                let taxResult = GSTEngine.calculateTax(
                    price: purchaseItem.costPrice,
                    quantity: purchaseItem.quantity,
                    gstRate: gstRate,
                    cessRate: item.cessRate ?? 0,
                    isInterState: interState,
                    pricesIncludeGST: false
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
            
            // Services: no batch or stock tracking
            if !item.isService {
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
                item.currentStock += purchaseItem.quantity
                item.lastRestockDate = now
            }

            item.defaultCostPrice = purchaseItem.costPrice
            item.defaultSellingPrice = purchaseItem.sellingPrice
            item.defaultPriceUpdatedAt = now
            inMemoryItems[purchaseItem.itemID] = item
            
            totalPurchaseAmount += lineRupees(quantity: purchaseItem.quantity, rate: purchaseItem.costPrice)
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
            isInterState: isInterState,
            totalTaxableValue: isGST && hasGSTItems ? billTotalTaxable : nil,
            totalCGST: isGST && hasGSTItems ? billTotalCGST : nil,
            totalSGST: isGST && hasGSTItems ? billTotalSGST : nil,
            totalIGST: isGST && hasGSTItems ? billTotalIGST : nil,
            totalCess: isGST && hasGSTItems ? billTotalCess : nil,
            isReverseCharge: false
        )
        
        try db.performWrite {
            try db.insertTransaction(transaction)
            try db.insertTransactionItems(allTxItems)
            for batch in allBatches {
                try db.insertBatch(batch)
            }
            for item in inMemoryItems.values {
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
        }
        
        return transaction
    }

    
    

    struct BatchConsumptionResult {
        let consumptions: [(batch: ItemBatch, consumed: Double)]
        let updatedBatches: [ItemBatch]
        let totalCost: Double
        let totalRevenue: Double
    }

   
    func consumeBatchesFIFO(
        itemID: UUID,
        quantity: Double,
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
        var consumptions: [(batch: ItemBatch, consumed: Double)] = []
        var totalCost: Double = 0
        var totalRevenue: Double = 0

        for i in batches.indices where remaining > 0 {
            let consumeQty = min(batches[i].quantityRemaining, remaining)
            batches[i].quantityRemaining -= consumeQty
            consumptions.append((batch: batches[i], consumed: consumeQty))

            totalCost += lineRupees(quantity: consumeQty, rate: batches[i].costPrice)
            let price = sellingPrice ?? batches[i].sellingPrice
            totalRevenue += lineRupees(quantity: consumeQty, rate: price)
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
        quantity: Double,
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
        var batchConsumptions: [(batch: ItemBatch, consumed: Double)] = []
        var totalCost: Double = 0
        var totalRevenue: Double = 0
        
        for i in batches.indices where remainingToSell > 0 {
            var batch = batches[i]
            
            let consumeQty = min(batch.quantityRemaining, remainingToSell)
            
            batch.quantityRemaining -= consumeQty
            batches[i] = batch
            
            // Track consumption
            batchConsumptions.append((batch: batch, consumed: consumeQty))
            let batchRevenue = lineRupees(quantity: consumeQty, rate: batch.sellingPrice)
            let batchCost = lineRupees(quantity: consumeQty, rate: batch.costPrice)
            
            totalRevenue += batchRevenue
            totalCost += batchCost
            
            remainingToSell -= consumeQty
        }
        
        let avgSellingPrice = totalRevenue / quantity
        let avgCostPrice = totalCost / quantity
        let totalProfit = totalRevenue - totalCost
        
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let buyerPOS = try resolveBuyerPlaceOfSupply(
            isGST: isGST,
            explicit: buyerStateCode,
            gstin: buyerGSTIN,
            shopStateCode: settings.businessStateCode
        )
        let isInterState = try gstInterStateOrThrow(
            isGST: isGST,
            sellerCode: settings.businessStateCode,
            buyerCode: buyerPOS
        )

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
            placeOfSupply: isGST ? (IndianStates.stateByCode(buyerPOS ?? "")?.name ?? settings.businessState) : nil,
            placeOfSupplyCode: isGST ? buyerPOS : nil,
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
        
        try db.performWrite {
            try db.insertTransaction(transaction)
            try db.insertTransactionItems([txItem])
            try db.insertSaleItemBatches(saleItemBatches)
            for consumption in batchConsumptions {
                try db.decrementBatchQuantity(id: consumption.batch.id, by: consumption.consumed)
            }
            let remainingBatches = try db.getBatches(for: itemID)
            item.currentStock = remainingBatches.reduce(0) { $0 + $1.quantityRemaining }
            item.salesCount = (item.salesCount ?? 0) + quantity
            try db.updateItem(item)
            try db.updateSettings(settings)
            let summary = try updatedDailySummary(
                date: day,
                revenue: totalRevenue,
                profit: totalProfit,
                itemsSold: quantity
            )
            try db.upsertDailySummary(summary)
        }
    }
    
    func getExpiryAlerts() throws -> [ExpiryAlert] {
        let settings = try db.getSettings()
        let now = Date()
        
        // Exclude services
        let items = try getAllItems().filter { $0.isActive && !$0.isService }
        
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
        // Exclude services
        let items = try getAllItems()
            .filter { $0.isActive && !$0.isService && $0.isLowStock }
        
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
        itemsSold: Double = 0,
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
    

    func reconcileAllStock() {
        do {
            let items: [Item]
            if let sqlite = db as? SQLiteDatabase {
                items = try sqlite.getAllItemsIncludingInactive()
            } else {
                items = try db.getAllItems()
            }
            for var item in items {
                let batches = try db.getBatches(for: item.id)
                let trueStock = batches.reduce(0) { $0 + $1.quantityRemaining }
                if item.currentStock != trueStock {
                    print("[DataModel] Reconciling \(item.name): \(item.currentStock) → \(trueStock)")
                    item.currentStock = trueStock
                    try db.updateItem(item)
                }
            }
        } catch {
            print("[DataModel] Stock reconciliation error: \(error)")
        }
    }
    
    func deleteItem(id: UUID) throws {
        try db.deleteItem(id: id)
    }
    
    func addMultiItemSale(
        items: [(itemID: UUID, quantity: Double, sellingPrice: Double)],
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
        let totalItemsSold = Set(items.filter { $0.quantity > 0 }.map { $0.itemID }).count
        var inMemoryBatches: [UUID: [ItemBatch]] = [:]
        var inMemoryItems: [UUID: Item] = [:]

        // GST accumulators
        let isGST = settings.isGSTRegistered && settings.gstScheme != "composition"
        let buyerPOS = try resolveBuyerPlaceOfSupply(
            isGST: isGST,
            explicit: buyerStateCode,
            gstin: buyerGSTIN,
            shopStateCode: settings.businessStateCode
        )
        let isInterState = try gstInterStateOrThrow(
            isGST: isGST,
            sellerCode: settings.businessStateCode,
            buyerCode: buyerPOS
        )
        var gstItemResults: [(gstRate: Double, result: ItemTaxResult)] = []
        var billTotalTaxable: Double = 0
        var billTotalCGST: Double = 0
        var billTotalSGST: Double = 0
        var billTotalIGST: Double = 0
        var billTotalCess: Double = 0
        let saleSubtotal = items.reduce(0.0) { $0 + lineRupees(quantity: max(0, $1.quantity), rate: $1.sellingPrice) }
        

        var outOfStockItemNames: [String] = []
        var preCheckBatches: [UUID: [ItemBatch]] = [:]
        
        for saleItem in items {
            guard saleItem.quantity > 0 else { continue }

            // Skip stock pre-check for service items
            if let item = try db.getItem(id: saleItem.itemID), item.isService { continue }

            var batches = try preCheckBatches[saleItem.itemID] ?? db.getBatches(for: saleItem.itemID).filter { $0.quantityRemaining > 0 }
            let totalAvailable = batches.reduce(0) { $0 + $1.quantityRemaining }
            
            if totalAvailable < saleItem.quantity {
                if let item = try db.getItem(id: saleItem.itemID) {
                    outOfStockItemNames.append(item.name)
                }
            } else {
                // Simulate consumption for pre-check
                var remaining = saleItem.quantity
                for i in batches.indices where remaining > 0 {
                    let consumeQty = min(batches[i].quantityRemaining, remaining)
                    batches[i].quantityRemaining -= consumeQty
                    remaining -= consumeQty
                }
                preCheckBatches[saleItem.itemID] = batches
            }
        }
        
        if !outOfStockItemNames.isEmpty {
            throw DataModelError.insufficientStockMulti(items: outOfStockItemNames)
        }
        
        for saleItem in items {
            guard saleItem.quantity > 0 else { continue }
            
            var item: Item
            if let cached = inMemoryItems[saleItem.itemID] {
                item = cached
            } else if let dbItem = try db.getItem(id: saleItem.itemID) {
                item = dbItem
            } else {
                throw DataModelError.itemNotFound
            }

            let itemRevenue = lineRupees(quantity: saleItem.quantity, rate: saleItem.sellingPrice)
            var itemCost: Double = 0
            var avgCostPrice: Double = item.defaultCostPrice
            var batchConsumptions: [(batch: ItemBatch, consumed: Double)] = []
            let txItemID = UUID()

            if item.isService {
                // Services: no FIFO, cost = default cost price
                itemCost = lineRupees(quantity: saleItem.quantity, rate: item.defaultCostPrice)
                avgCostPrice = item.defaultCostPrice
            } else {
                // Goods: FIFO batch consumption
                var batches = try inMemoryBatches[saleItem.itemID] ?? db.getBatches(for: saleItem.itemID)
                    .filter { $0.quantityRemaining > 0 }
                    .sorted { b1, b2 in
                        if let e1 = b1.expiryDate, let e2 = b2.expiryDate { return e1 < e2 }
                        if b1.expiryDate == nil && b2.expiryDate == nil { return b1.receivedDate < b2.receivedDate }
                        return b1.expiryDate != nil
                    }

                var remaining = saleItem.quantity
                for i in batches.indices where remaining > 0 {
                    let consumeQty = min(batches[i].quantityRemaining, remaining)
                    batches[i].quantityRemaining -= consumeQty
                    batchConsumptions.append((batch: batches[i], consumed: consumeQty))
                    itemCost += lineRupees(quantity: consumeQty, rate: batches[i].costPrice)
                    remaining -= consumeQty
                }
                avgCostPrice = saleItem.quantity > 0 ? itemCost / saleItem.quantity : 0
                inMemoryBatches[saleItem.itemID] = batches
            }

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
            if isGST {
                guard let gstRate = item.gstRate else {
                    throw DataModelError.custom("Set a GST rate for \(item.name) before selling on a GST invoice.")
                }
                let taxResult = GSTEngine.calculateTax(
                    price: GSTEngine.discountedUnitPrice(
                        lineRevenue: lineRupees(quantity: saleItem.quantity, rate: saleItem.sellingPrice),
                        subtotal: saleSubtotal,
                        discount: discount,
                        quantity: saleItem.quantity
                    ),
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
            
            // Batch tracking (goods only)
            if !item.isService {
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
            }

            item.salesCount = (item.salesCount ?? 0) + saleItem.quantity
            inMemoryItems[saleItem.itemID] = item
            
            totalRevenue += itemRevenue
            totalCost += itemCost
        }
        if isGST && !gstItemResults.isEmpty {
            let breakup = GSTEngine.generateBreakup(itemResults: gstItemResults)
            billTotalTaxable = breakup.totalTaxableValue
            billTotalCGST = breakup.totalCGST
            billTotalSGST = breakup.totalSGST
            billTotalIGST = breakup.totalIGST
            billTotalCess = breakup.totalCess
        }
        let grandTotal: Double
        if isGST && !gstItemResults.isEmpty {
            grandTotal = rupees(billTotalTaxable + billTotalCGST + billTotalSGST + billTotalIGST + billTotalCess + adjustment)
        } else {
            grandTotal = rupees(totalRevenue - discount + adjustment)
        }
        let totalProfit = rupees(totalRevenue - totalCost)
        
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
            placeOfSupply: isGST ? (IndianStates.stateByCode(buyerPOS ?? "")?.name ?? settings.businessState) : nil,
            placeOfSupplyCode: isGST ? buyerPOS : nil,
            isInterState: isGST ? isInterState : nil,
            totalTaxableValue: isGST && !gstItemResults.isEmpty ? billTotalTaxable : nil,
            totalCGST: isGST && !gstItemResults.isEmpty ? billTotalCGST : nil,
            totalSGST: isGST && !gstItemResults.isEmpty ? billTotalSGST : nil,
            totalIGST: isGST && !gstItemResults.isEmpty ? billTotalIGST : nil,
            totalCess: isGST && !gstItemResults.isEmpty ? billTotalCess : nil,
            isReverseCharge: false
        )
        
        try db.performWrite {
            try db.insertTransaction(transaction)
            try db.insertTransactionItems(allTxItems)
            try db.insertSaleItemBatches(allSaleItemBatches)
            for sib in allSaleItemBatches {
                try db.decrementBatchQuantity(id: sib.batchID, by: sib.quantityConsumed)
            }
            for item in inMemoryItems.values {
                try db.updateItem(item)
            }
            if invoiceNumber == nil {
                try db.updateSettings(settings)
            }
            let summary = try updatedDailySummary(
                date: day,
                revenue: grandTotal,
                profit: totalProfit,
                itemsSold: Double(totalItemsSold)
            )
            try db.upsertDailySummary(summary)
        }
        
        return transaction
    }
    
    // MARK: - DASHBOARD & TAB STATS

    struct TodayStats {
        var revenue: Double = 0
        var profit: Double = 0
        var purchaseTotal: Double = 0
        var saleCount: Int = 0
        var itemsSold: Double = 0
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
                    stats.profit += rupees(
                        lineRupees(quantity: item.quantity, rate: item.sellingPricePerUnit ?? 0)
                            - lineRupees(quantity: item.quantity, rate: item.costPricePerUnit ?? 0)
                    )
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
    func getTodayItemsSoldCount() -> Double { getTodayStats().itemsSold }
    func getTotalInvestment() -> Double {
        guard let items = try? db.getAllItems() else { return 0 }
        var total: Double = 0
        for item in items where !item.isService {
            if let batches = try? db.getBatches(for: item.id) {
                for batch in batches where batch.quantityRemaining > 0 {
                    total += batch.quantityRemaining * batch.costPrice
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
    

    func addQuickSale(
        itemName: String,
        quantity: Double,
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
            totalAmount: lineRupees(quantity: quantity, rate: sellingPrice),
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
            revenue: lineRupees(quantity: quantity, rate: sellingPrice),
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
        lowStockThreshold: Double,
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
            currentStock: 0,  
            createdDate: now,
            lastRestockDate: nil,
            isActive: true
        )
        

        let purchaseTxID = UUID()
        let virtualPurchase = Transaction(
            id: purchaseTxID,
            type: .purchase,
            date: incompleteSale.createdAt,  // Backdated to sale date
            invoiceNumber: "RETRO-\(UUID().uuidString.prefix(8))",
            customerName: nil,
            customerPhone: nil,
            supplierName: supplierName,
            totalAmount: lineRupees(quantity: incompleteSale.quantity, rate: costPrice),
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
        let profit = rupees(
            lineRupees(quantity: incompleteSale.quantity, rate: incompleteSale.sellingPricePerUnit)
                - lineRupees(quantity: incompleteSale.quantity, rate: costPrice)
        )
        
        let summary = try updatedDailySummary(
            date: saleDate,
            revenue: 0,  
            profit: profit, 
            itemsSold: 0  
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
