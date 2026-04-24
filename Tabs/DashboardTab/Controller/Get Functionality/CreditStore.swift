import Foundation

// MARK: - CreditStore — Persistence Singleton for Credit System

final class CreditStore {
    
    static let shared = CreditStore()

    /// Reference to the shared SQLite database
    private var db: SQLiteDatabase { SQLiteDatabase.shared }
    
    private init() {}

    private func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Customer CRUD
    // ─────────────────────────────────────────────
    
    func addCustomer(_ customer: Customer) {
        var c = customer
        c.netBalance = 0
        db.insertCustomer(c)
    }
    
    func updateCustomer(_ customer: Customer) {
        db.updateCustomerRecord(customer)
    }
    
    func deleteCustomer(_ customer: Customer) {
        db.deleteCustomerCascade(id: customer.id)
    }
    
    func getCustomer(id: UUID) -> Customer? {
        guard var customer = db.getCustomerByID(id) else { return nil }
        customer.netBalance = getNetBalance(forCustomer: id)
        return customer
    }
    
    func getAllCustomers() -> [Customer] {
        return db.getAllCustomers().map { c in
            var copy = c
            copy.netBalance = getNetBalance(forCustomer: c.id)
            return copy
        }
    }

    @discardableResult
    func ensureCustomer(named rawName: String?, defaultName: String = "Customer") -> Customer {
        let resolvedName = normalizedName(rawName) ?? defaultName

        let all = db.getAllCustomers()
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            return existing
        }

        let customer = Customer(id: UUID(), name: resolvedName, phone: nil)
        addCustomer(customer)
        return customer
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Supplier CRUD
    // ─────────────────────────────────────────────
    
    func addSupplier(_ supplier: Supplier) {
        var s = supplier
        s.netBalance = 0
        db.insertSupplier(s)
    }
    
    func updateSupplier(_ supplier: Supplier) {
        db.updateSupplierRecord(supplier)
    }
    
    func deleteSupplier(_ supplier: Supplier) {
        db.deleteSupplierCascade(id: supplier.id)
    }
    
    func getSupplier(id: UUID) -> Supplier? {
        guard var supplier = db.getSupplierByID(id) else { return nil }
        supplier.netBalance = getNetBalance(forSupplier: id)
        return supplier
    }
    
    func getAllSuppliers() -> [Supplier] {
        return db.getAllSuppliersFromDB().map { s in
            var copy = s
            copy.netBalance = getNetBalance(forSupplier: s.id)
            return copy
        }
    }

    @discardableResult
    func ensureSupplier(named rawName: String?, defaultName: String = "Supplier") -> Supplier {
        let resolvedName = normalizedName(rawName) ?? defaultName

        let all = db.getAllSuppliersFromDB()
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            return existing
        }

        let supplier = Supplier(id: UUID(), name: resolvedName, phone: nil)
        addSupplier(supplier)
        return supplier
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Customer Payment CRUD
    // ─────────────────────────────────────────────
    
    func addPayment(_ payment: Payment) {
        db.insertCustomerPayment(payment)
    }
    
    func getPayments(forCustomer customerID: UUID) -> [Payment] {
        return db.getCustomerPayments(forCustomer: customerID)
    }
    
    /// Net balance for a customer:
    /// Positive = customer owes you (you'll receive)
    /// Negative = you owe the customer
    ///
    /// Customer ledger meaning:
    /// - .paid: you gave value to customer (e.g. credit sale) => receivable increases
    /// - .received: customer paid you back => receivable decreases
    func getNetBalance(forCustomer customerID: UUID) -> Double {
        let payments = db.getCustomerPayments(forCustomer: customerID)
        var balance: Double = 0
        for p in payments {
            switch p.type {
            case .received:
                balance -= p.amount    // Customer paid you back → receivable goes down
            case .paid:
                balance += p.amount    // You gave customer value → receivable goes up
            }
        }
        return balance
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Supplier Payment CRUD
    // ─────────────────────────────────────────────
    
    func addSupplierPayment(_ payment: SupplierPayment) {
        db.insertSupplierPaymentRecord(payment)
    }

    func addCreditSale(amount: Double, customerName: String?, note: String? = nil) {
        guard amount > 0 else { return }
        let customer = ensureCustomer(named: customerName, defaultName: "Customer")
        let payment = Payment(
            id: UUID(),
            customerID: customer.id,
            amount: amount,
            date: Date(),
            type: .paid,
            note: note
        )
        addPayment(payment)
    }

    func addCreditPurchase(amount: Double, supplierName: String?, note: String? = nil) {
        guard amount > 0 else { return }
        let supplier = ensureSupplier(named: supplierName, defaultName: "Supplier")
        let payment = SupplierPayment(
            id: UUID(),
            supplierID: supplier.id,
            amount: amount,
            date: Date(),
            type: .received,
            note: note
        )
        addSupplierPayment(payment)
    }
    
    func getPayments(forSupplier supplierID: UUID) -> [SupplierPayment] {
        return db.getSupplierPayments(forSupplier: supplierID)
    }
    
    /// Net balance for a supplier:
    /// Positive = supplier gave you more than you paid → you owe them
    /// Negative = you paid more than they gave
    func getNetBalance(forSupplier supplierID: UUID) -> Double {
        let payments = db.getSupplierPayments(forSupplier: supplierID)
        var balance: Double = 0
        for p in payments {
            switch p.type {
            case .received:
                balance += p.amount    // Goods/money received from supplier → you owe more
            case .paid:
                balance -= p.amount    // Money paid to supplier → you owe less
            }
        }
        return balance
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Aggregate Helpers
    // ─────────────────────────────────────────────
    
    /// Total amount all customers owe you
    func getTotalReceivable() -> Double {
        let customers = db.getAllCustomers()
        return customers.reduce(0.0) { sum, c in
            let balance = getNetBalance(forCustomer: c.id)
            return sum + max(0, balance)
        }
    }
    
    /// Total amount you owe all suppliers
    func getTotalPayable() -> Double {
        let suppliers = db.getAllSuppliersFromDB()
        return suppliers.reduce(0.0) { sum, s in
            let balance = getNetBalance(forSupplier: s.id)
            return sum + max(0, balance)
        }
    }
}
