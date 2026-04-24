import Foundation

extension Transaction {
    func toBillingDetails() -> BillingDetails {
        let db = AppDataModel.shared.dataModel.db
        let txItems = (try? db.getTransactionItems(for: self.id)) ?? []
        let settings = (try? db.getSettings()) ?? AppSettings(
            invoicePrefix: "INV", invoiceNumberCounter: 1, includeYearInInvoice: false,
            businessName: "My Shop", expiryNoticeDays: 14, expiryWarningDays: 7, expiryCriticalDays: 3
        )

        let billingItems: [TransactionItem] = txItems

        // Build GST breakup if GST is registered and items have tax data
        var taxBreakup: GSTBreakup? = nil
        if settings.isGSTRegistered {
            let itemResults: [(gstRate: Double, result: ItemTaxResult)] = txItems.compactMap { item in
                guard let taxable = item.taxableValue, let rate = item.gstRate else { return nil }
                let result = ItemTaxResult(
                    taxableValue: taxable,
                    cgst: item.cgstAmount ?? 0,
                    sgst: item.sgstAmount ?? 0,
                    igst: item.igstAmount ?? 0,
                    cess: item.cessAmount ?? 0,
                    totalTax: (item.cgstAmount ?? 0) + (item.sgstAmount ?? 0) + (item.igstAmount ?? 0) + (item.cessAmount ?? 0),
                    totalWithTax: taxable + (item.cgstAmount ?? 0) + (item.sgstAmount ?? 0) + (item.igstAmount ?? 0) + (item.cessAmount ?? 0)
                )
                return (gstRate: rate, result: result)
            }
            if !itemResults.isEmpty {
                taxBreakup = GSTEngine.generateBreakup(itemResults: itemResults)
            }
        }

        return BillingDetails(
            customerName: customerName ?? supplierName ?? (type == .sale ? "Cash Sale" : "Supplier"),
            items: billingItems,
            discount: 0,
            adjustment: 0,
            descriptionText: notes,
            invoiceDate: date,
            invoiceNumber: invoiceNumber,
            transactionType: type,
            isCreditSale: false,
            sellerGSTIN: settings.isGSTRegistered ? settings.gstNumber : nil,
            sellerState: settings.businessState,
            buyerGSTIN: buyerGSTIN,
            buyerState: placeOfSupply,
            placeOfSupply: placeOfSupply,
            isInterState: isInterState ?? false,
            isCompositionScheme: settings.gstScheme == "composition",
            taxBreakup: taxBreakup
        )
    }
}
