import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase: Database {

    static let shared = SQLiteDatabase()

    private var db: OpaquePointer?
    let dbPath: String

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()


    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = docs.appendingPathComponent("ledgile.sqlite")
        dbPath = dbURL.path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[SQLiteDB] ERROR: Could not open database at \(dbPath)")
            return
        }

        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")
        createTables()
        migrateGSTColumns()
        capitalizeExistingItemNames()
    }

    deinit {
        sqlite3_close(db)
    }


    private func createTables() {
        let ddl = """
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            unit TEXT NOT NULL,
            barcode TEXT,
            default_cost_price REAL NOT NULL,
            default_selling_price REAL NOT NULL,
            default_price_updated_at TEXT NOT NULL,
            low_stock_threshold INTEGER NOT NULL,
            current_stock INTEGER NOT NULL,
            created_date TEXT NOT NULL,
            last_restock_date TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            sales_count INTEGER,
            sales_tier INTEGER
        );

        CREATE TABLE IF NOT EXISTS item_batches (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            purchase_transaction_id TEXT NOT NULL,
            quantity_purchased INTEGER NOT NULL,
            quantity_remaining INTEGER NOT NULL,
            cost_price REAL NOT NULL,
            selling_price REAL NOT NULL,
            expiry_date TEXT,
            received_date TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS product_photos (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            local_path TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            date TEXT NOT NULL,
            invoice_number TEXT NOT NULL,
            customer_name TEXT,
            customer_phone TEXT,
            supplier_name TEXT,
            total_amount REAL NOT NULL,
            notes TEXT
        );

        CREATE TABLE IF NOT EXISTS transaction_items (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            unit TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            selling_price_per_unit REAL,
            cost_price_per_unit REAL,
            created_date TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sale_item_batches (
            id TEXT PRIMARY KEY,
            transaction_item_id TEXT NOT NULL,
            batch_id TEXT NOT NULL,
            quantity_consumed INTEGER NOT NULL,
            cost_price_used REAL NOT NULL,
            selling_price_used REAL NOT NULL,
            batch_received_date TEXT NOT NULL,
            batch_expiry_date TEXT
        );

        CREATE TABLE IF NOT EXISTS incomplete_sale_items (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL,
            transaction_item_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            selling_price_per_unit REAL NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            completed_at TEXT,
            unit TEXT,
            cost_price_per_unit REAL,
            supplier_name TEXT,
            expiry_date TEXT,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS daily_summaries (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL UNIQUE,
            total_revenue REAL NOT NULL,
            total_profit REAL NOT NULL,
            sales_transaction_count INTEGER NOT NULL,
            items_sold_count INTEGER NOT NULL,
            total_purchase_amount REAL NOT NULL,
            purchase_transaction_count INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY DEFAULT 'main',
            invoice_prefix TEXT NOT NULL,
            invoice_number_counter INTEGER NOT NULL,
            current_year INTEGER,
            include_year_in_invoice INTEGER NOT NULL DEFAULT 0,
            owner_name TEXT,
            business_name TEXT NOT NULL,
            profile_name TEXT,
            business_phone TEXT,
            profile_image_data BLOB,
            business_address TEXT,
            gst_number TEXT,
            expiry_notice_days INTEGER NOT NULL DEFAULT 14,
            expiry_warning_days INTEGER NOT NULL DEFAULT 7,
            expiry_critical_days INTEGER NOT NULL DEFAULT 3
        );

        CREATE TABLE IF NOT EXISTS customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            profile_image_data BLOB
        );

        CREATE TABLE IF NOT EXISTS suppliers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            profile_image_data BLOB
        );

        CREATE TABLE IF NOT EXISTS customer_payments (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            type TEXT NOT NULL,
            note TEXT
        );

        CREATE TABLE IF NOT EXISTS supplier_payments (
            id TEXT PRIMARY KEY,
            supplier_id TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            type TEXT NOT NULL,
            note TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_batches_item ON item_batches(item_id);
        CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);
        CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type);
        CREATE INDEX IF NOT EXISTS idx_tx_items_tx ON transaction_items(transaction_id);
        CREATE INDEX IF NOT EXISTS idx_tx_items_item ON transaction_items(item_id);
        CREATE INDEX IF NOT EXISTS idx_sib_tx_item ON sale_item_batches(transaction_item_id);
        CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_summaries(date);
        CREATE INDEX IF NOT EXISTS idx_photos_item ON product_photos(item_id);
        CREATE INDEX IF NOT EXISTS idx_cpay_customer ON customer_payments(customer_id);
        CREATE INDEX IF NOT EXISTS idx_spay_supplier ON supplier_payments(supplier_id);
        CREATE INDEX IF NOT EXISTS idx_incomplete_status ON incomplete_sale_items(is_completed);
        """

        exec(ddl)
    }


    private func migrateGSTColumns() {
        let key = "didMigrateGSTColumns_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        exec("ALTER TABLE items ADD COLUMN hsn_code TEXT")
        exec("ALTER TABLE items ADD COLUMN gst_rate REAL")
        exec("ALTER TABLE items ADD COLUMN cess_rate REAL")

        exec("ALTER TABLE transactions ADD COLUMN buyer_gstin TEXT")
        exec("ALTER TABLE transactions ADD COLUMN place_of_supply TEXT")
        exec("ALTER TABLE transactions ADD COLUMN place_of_supply_code TEXT")
        exec("ALTER TABLE transactions ADD COLUMN is_inter_state INTEGER")
        exec("ALTER TABLE transactions ADD COLUMN total_taxable_value REAL")
        exec("ALTER TABLE transactions ADD COLUMN total_cgst REAL")
        exec("ALTER TABLE transactions ADD COLUMN total_sgst REAL")
        exec("ALTER TABLE transactions ADD COLUMN total_igst REAL")
        exec("ALTER TABLE transactions ADD COLUMN total_cess REAL")
        exec("ALTER TABLE transactions ADD COLUMN is_reverse_charge INTEGER DEFAULT 0")

        exec("ALTER TABLE transaction_items ADD COLUMN hsn_code TEXT")
        exec("ALTER TABLE transaction_items ADD COLUMN gst_rate REAL")
        exec("ALTER TABLE transaction_items ADD COLUMN taxable_value REAL")
        exec("ALTER TABLE transaction_items ADD COLUMN cgst_amount REAL")
        exec("ALTER TABLE transaction_items ADD COLUMN sgst_amount REAL")
        exec("ALTER TABLE transaction_items ADD COLUMN igst_amount REAL")
        exec("ALTER TABLE transaction_items ADD COLUMN cess_amount REAL")

        exec("ALTER TABLE app_settings ADD COLUMN is_gst_registered INTEGER NOT NULL DEFAULT 0")
        exec("ALTER TABLE app_settings ADD COLUMN gst_scheme TEXT")
        exec("ALTER TABLE app_settings ADD COLUMN business_state TEXT")
        exec("ALTER TABLE app_settings ADD COLUMN business_state_code TEXT")
        exec("ALTER TABLE app_settings ADD COLUMN prices_include_gst INTEGER NOT NULL DEFAULT 1")
        exec("ALTER TABLE app_settings ADD COLUMN default_gst_rate REAL")
        exec("ALTER TABLE app_settings ADD COLUMN composition_rate REAL")

        UserDefaults.standard.set(true, forKey: key)
        print("[SQLiteDB] ✅ GST columns migration complete.")
    }


    private func capitalizeExistingItemNames() {
        let key = "didCapitalizeItemNames_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        if let stmt = prepare("SELECT id, name FROM items") {
            var updates: [(String, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = readString(stmt, 0)
                let name = readString(stmt, 1)
                let capitalized = name.capitalized
                if capitalized != name {
                    updates.append((id, capitalized))
                }
            }
            sqlite3_finalize(stmt)
            for (id, newName) in updates {
                if let upd = prepare("UPDATE items SET name=? WHERE id=?") {
                    bindText(upd, 1, newName)
                    bindText(upd, 2, id)
                    sqlite3_step(upd)
                    sqlite3_finalize(upd)
                }
            }
        }

        if let stmt = prepare("SELECT id, item_name FROM transaction_items") {
            var updates: [(String, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = readString(stmt, 0)
                let name = readString(stmt, 1)
                let capitalized = name.capitalized
                if capitalized != name {
                    updates.append((id, capitalized))
                }
            }
            sqlite3_finalize(stmt)
            for (id, newName) in updates {
                if let upd = prepare("UPDATE transaction_items SET item_name=? WHERE id=?") {
                    bindText(upd, 1, newName)
                    bindText(upd, 2, id)
                    sqlite3_step(upd)
                    sqlite3_finalize(upd)
                }
            }
        }

        if let stmt = prepare("SELECT id, item_name FROM incomplete_sale_items") {
            var updates: [(String, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = readString(stmt, 0)
                let name = readString(stmt, 1)
                let capitalized = name.capitalized
                if capitalized != name {
                    updates.append((id, capitalized))
                }
            }
            sqlite3_finalize(stmt)
            for (id, newName) in updates {
                if let upd = prepare("UPDATE incomplete_sale_items SET item_name=? WHERE id=?") {
                    bindText(upd, 1, newName)
                    bindText(upd, 2, id)
                    sqlite3_step(upd)
                    sqlite3_finalize(upd)
                }
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        print("[SQLiteDB] ✅ One-time item name capitalization complete.")
    }


    @discardableResult
    func exec(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[SQLiteDB] exec error: \(msg)")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[SQLiteDB] prepare error: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return stmt
    }


    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ val: String) {
        sqlite3_bind_text(stmt, idx, val, -1, SQLITE_TRANSIENT)
    }
    private func bindOptText(_ stmt: OpaquePointer, _ idx: Int32, _ val: String?) {
        if let v = val { bindText(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindUUID(_ stmt: OpaquePointer, _ idx: Int32, _ val: UUID) {
        bindText(stmt, idx, val.uuidString)
    }
    private func bindInt(_ stmt: OpaquePointer, _ idx: Int32, _ val: Int) {
        sqlite3_bind_int64(stmt, idx, Int64(val))
    }
    private func bindOptInt(_ stmt: OpaquePointer, _ idx: Int32, _ val: Int?) {
        if let v = val { bindInt(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindDouble(_ stmt: OpaquePointer, _ idx: Int32, _ val: Double) {
        sqlite3_bind_double(stmt, idx, val)
    }
    private func bindOptDouble(_ stmt: OpaquePointer, _ idx: Int32, _ val: Double?) {
        if let v = val { bindDouble(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindBool(_ stmt: OpaquePointer, _ idx: Int32, _ val: Bool) {
        sqlite3_bind_int(stmt, idx, val ? 1 : 0)
    }
    private func bindDate(_ stmt: OpaquePointer, _ idx: Int32, _ val: Date) {
        bindText(stmt, idx, Self.iso8601.string(from: val))
    }
    private func bindOptDate(_ stmt: OpaquePointer, _ idx: Int32, _ val: Date?) {
        if let v = val { bindDate(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindBlob(_ stmt: OpaquePointer, _ idx: Int32, _ val: Data?) {
        if let d = val {
            d.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(d.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }


    private func readUUID(_ stmt: OpaquePointer, _ col: Int32) -> UUID {
        UUID(uuidString: readString(stmt, col)) ?? UUID()
    }
    private func readString(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }
    private func readOptString(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : readString(stmt, col)
    }
    private func readInt(_ stmt: OpaquePointer, _ col: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, col))
    }
    private func readOptInt(_ stmt: OpaquePointer, _ col: Int32) -> Int? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : readInt(stmt, col)
    }
    private func readDouble(_ stmt: OpaquePointer, _ col: Int32) -> Double {
        sqlite3_column_double(stmt, col)
    }
    private func readOptDouble(_ stmt: OpaquePointer, _ col: Int32) -> Double? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : readDouble(stmt, col)
    }
    private func readBool(_ stmt: OpaquePointer, _ col: Int32) -> Bool {
        sqlite3_column_int(stmt, col) != 0
    }
    private func readDate(_ stmt: OpaquePointer, _ col: Int32) -> Date {
        let s = readString(stmt, col)
        return Self.iso8601.date(from: s) ?? Self.iso8601NoFrac.date(from: s) ?? Date()
    }
    private func readOptDate(_ stmt: OpaquePointer, _ col: Int32) -> Date? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return readDate(stmt, col)
    }
    private func readBlob(_ stmt: OpaquePointer, _ col: Int32) -> Data? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_blob(stmt, col) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, col))
        return Data(bytes: ptr, count: count)
    }


    private func readItem(_ s: OpaquePointer) -> Item {
        Item(
            id:                     readUUID(s, 0),
            name:                   readString(s, 1),
            unit:                   readString(s, 2),
            barcode:                readOptString(s, 3),
            defaultCostPrice:       readDouble(s, 4),
            defaultSellingPrice:    readDouble(s, 5),
            defaultPriceUpdatedAt:  readDate(s, 6),
            lowStockThreshold:      readInt(s, 7),
            currentStock:           readInt(s, 8),
            createdDate:            readDate(s, 9),
            lastRestockDate:        readOptDate(s, 10),
            isActive:               readBool(s, 11),
            salesCount:             readOptInt(s, 12),
            salesTier:              readOptInt(s, 13),
            hsnCode:                readOptString(s, 14),
            gstRate:                readOptDouble(s, 15),
            cessRate:               readOptDouble(s, 16)
        )
    }

    private func readBatch(_ s: OpaquePointer) -> ItemBatch {
        ItemBatch(
            id:                     readUUID(s, 0),
            itemID:                 readUUID(s, 1),
            purchaseTransactionID:  readUUID(s, 2),
            quantityPurchased:      readInt(s, 3),
            quantityRemaining:      readInt(s, 4),
            costPrice:              readDouble(s, 5),
            sellingPrice:           readDouble(s, 6),
            expiryDate:             readOptDate(s, 7),
            receivedDate:           readDate(s, 8)
        )
    }

    private func readTransaction(_ s: OpaquePointer) -> Transaction {
        Transaction(
            id:                 readUUID(s, 0),
            type:               TransactionType(rawValue: readString(s, 1)) ?? .sale,
            date:               readDate(s, 2),
            invoiceNumber:      readString(s, 3),
            customerName:       readOptString(s, 4),
            customerPhone:      readOptString(s, 5),
            supplierName:       readOptString(s, 6),
            totalAmount:        readDouble(s, 7),
            notes:              readOptString(s, 8),
            buyerGSTIN:         readOptString(s, 9),
            placeOfSupply:      readOptString(s, 10),
            placeOfSupplyCode:  readOptString(s, 11),
            isInterState:       sqlite3_column_type(s, 12) == SQLITE_NULL ? nil : readBool(s, 12),
            totalTaxableValue:  readOptDouble(s, 13),
            totalCGST:          readOptDouble(s, 14),
            totalSGST:          readOptDouble(s, 15),
            totalIGST:          readOptDouble(s, 16),
            totalCess:          readOptDouble(s, 17),
            isReverseCharge:    sqlite3_column_type(s, 18) == SQLITE_NULL ? nil : readBool(s, 18)
        )
    }

    private func readTransactionItem(_ s: OpaquePointer) -> TransactionItem {
        TransactionItem(
            id:                  readUUID(s, 0),
            transactionID:       readUUID(s, 1),
            itemID:              readUUID(s, 2),
            itemName:            readString(s, 3),
            unit:                readString(s, 4),
            quantity:            readInt(s, 5),
            sellingPricePerUnit: readOptDouble(s, 6),
            costPricePerUnit:    readOptDouble(s, 7),
            createdDate:         readDate(s, 8),
            hsnCode:             readOptString(s, 9),
            gstRate:             readOptDouble(s, 10),
            taxableValue:        readOptDouble(s, 11),
            cgstAmount:          readOptDouble(s, 12),
            sgstAmount:          readOptDouble(s, 13),
            igstAmount:          readOptDouble(s, 14),
            cessAmount:          readOptDouble(s, 15)
        )
    }

    private func readSaleItemBatch(_ s: OpaquePointer) -> SaleItemBatch {
        SaleItemBatch(
            id:                  readUUID(s, 0),
            transactionItemID:   readUUID(s, 1),
            batchID:             readUUID(s, 2),
            quantityConsumed:    readInt(s, 3),
            costPriceUsed:       readDouble(s, 4),
            sellingPriceUsed:    readDouble(s, 5),
            batchReceivedDate:   readDate(s, 6),
            batchExpiryDate:     readOptDate(s, 7)
        )
    }

    private func readIncompleteSaleItem(_ s: OpaquePointer) -> IncompleteSaleItem {
        IncompleteSaleItem(
            id:                  readUUID(s, 0),
            transactionID:       readUUID(s, 1),
            transactionItemID:   readUUID(s, 2),
            itemName:            readString(s, 3),
            quantity:            readInt(s, 4),
            sellingPricePerUnit: readDouble(s, 5),
            isCompleted:         readBool(s, 6),
            completedAt:         readOptDate(s, 7),
            unit:                readOptString(s, 8),
            costPricePerUnit:    readOptDouble(s, 9),
            supplierName:        readOptString(s, 10),
            expiryDate:          readOptDate(s, 11),
            createdAt:           readDate(s, 12)
        )
    }

    private func readDailySummary(_ s: OpaquePointer) -> DailySummary {
        DailySummary(
            id:                      readUUID(s, 0),
            date:                    readDate(s, 1),
            totalRevenue:            readDouble(s, 2),
            totalProfit:             readDouble(s, 3),
            salesTransactionCount:   readInt(s, 4),
            itemsSoldCount:          readInt(s, 5),
            totalPurchaseAmount:     readDouble(s, 6),
            purchaseTransactionCount:readInt(s, 7)
        )
    }

    private func readProductPhoto(_ s: OpaquePointer) -> ProductPhoto {
        ProductPhoto(
            id:        readUUID(s, 0),
            itemID:    readUUID(s, 1),
            localPath: readString(s, 2),
            createdAt: readDate(s, 3)
        )
    }

    private func readSettings(_ s: OpaquePointer) -> AppSettings {
        AppSettings(
            invoicePrefix:          readString(s, 0),
            invoiceNumberCounter:   readInt(s, 1),
            currentYear:            readOptInt(s, 2),
            includeYearInInvoice:   readBool(s, 3),
            ownerName:              readOptString(s, 4),
            businessName:           readString(s, 5),
            profileName:            readOptString(s, 6),
            businessPhone:          readOptString(s, 7),
            profileImageData:       readBlob(s, 8),
            businessAddress:        readOptString(s, 9),
            gstNumber:              readOptString(s, 10),
            expiryNoticeDays:       readInt(s, 11),
            expiryWarningDays:      readInt(s, 12),
            expiryCriticalDays:     readInt(s, 13),
            isGSTRegistered:        readBool(s, 14),
            gstScheme:              readOptString(s, 15),
            businessState:          readOptString(s, 16),
            businessStateCode:      readOptString(s, 17),
            pricesIncludeGST:       readBool(s, 18),
            defaultGSTRate:         readOptDouble(s, 19),
            compositionRate:        readOptDouble(s, 20)
        )
    }

    private func readCustomer(_ s: OpaquePointer) -> Customer {
        Customer(
            id:               readUUID(s, 0),
            name:             readString(s, 1),
            phone:            readOptString(s, 2),
            profileImageData: readBlob(s, 3)
        )
    }

    private func readSupplier(_ s: OpaquePointer) -> Supplier {
        Supplier(
            id:               readUUID(s, 0),
            name:             readString(s, 1),
            phone:            readOptString(s, 2),
            profileImageData: readBlob(s, 3)
        )
    }

    private func readPayment(_ s: OpaquePointer) -> Payment {
        Payment(
            id:         readUUID(s, 0),
            customerID: readUUID(s, 1),
            amount:     readDouble(s, 2),
            date:       readDate(s, 3),
            type:       CreditTransactionType(rawValue: readString(s, 4)) ?? .received,
            note:       readOptString(s, 5)
        )
    }

    private func readSupplierPayment(_ s: OpaquePointer) -> SupplierPayment {
        SupplierPayment(
            id:         readUUID(s, 0),
            supplierID: readUUID(s, 1),
            amount:     readDouble(s, 2),
            date:       readDate(s, 3),
            type:       CreditTransactionType(rawValue: readString(s, 4)) ?? .received,
            note:       readOptString(s, 5)
        )
    }


    func getItem(id: UUID) throws -> Item? {
        let sql = "SELECT id,name,unit,barcode,default_cost_price,default_selling_price,default_price_updated_at,low_stock_threshold,current_stock,created_date,last_restock_date,is_active,sales_count,sales_tier,hsn_code,gst_rate,cess_rate FROM items WHERE id=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readItem(stmt) : nil
    }

    func getAllItems() throws -> [Item] {
        let sql = "SELECT id,name,unit,barcode,default_cost_price,default_selling_price,default_price_updated_at,low_stock_threshold,current_stock,created_date,last_restock_date,is_active,sales_count,sales_tier,hsn_code,gst_rate,cess_rate FROM items"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Item] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readItem(stmt)) }
        return result
    }

    func insertItem(_ item: Item) throws {
        let sql = "INSERT INTO items (id,name,unit,barcode,default_cost_price,default_selling_price,default_price_updated_at,low_stock_threshold,current_stock,created_date,last_restock_date,is_active,sales_count,sales_tier,hsn_code,gst_rate,cess_rate) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, item.id)
        bindText(stmt, 2, item.name.capitalized)
        bindText(stmt, 3, item.unit)
        bindOptText(stmt, 4, item.barcode)
        bindDouble(stmt, 5, item.defaultCostPrice)
        bindDouble(stmt, 6, item.defaultSellingPrice)
        bindDate(stmt, 7, item.defaultPriceUpdatedAt)
        bindInt(stmt, 8, item.lowStockThreshold)
        bindInt(stmt, 9, item.currentStock)
        bindDate(stmt, 10, item.createdDate)
        bindOptDate(stmt, 11, item.lastRestockDate)
        bindBool(stmt, 12, item.isActive)
        bindOptInt(stmt, 13, item.salesCount)
        bindOptInt(stmt, 14, item.salesTier)
        bindOptText(stmt, 15, item.hsnCode)
        bindOptDouble(stmt, 16, item.gstRate)
        bindOptDouble(stmt, 17, item.cessRate)
        sqlite3_step(stmt)
    }

    func updateItem(_ item: Item) throws {
        let sql = "UPDATE items SET name=?,unit=?,barcode=?,default_cost_price=?,default_selling_price=?,default_price_updated_at=?,low_stock_threshold=?,current_stock=?,last_restock_date=?,is_active=?,sales_count=?,sales_tier=?,hsn_code=?,gst_rate=?,cess_rate=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, item.name.capitalized)
        bindText(stmt, 2, item.unit)
        bindOptText(stmt, 3, item.barcode)
        bindDouble(stmt, 4, item.defaultCostPrice)
        bindDouble(stmt, 5, item.defaultSellingPrice)
        bindDate(stmt, 6, item.defaultPriceUpdatedAt)
        bindInt(stmt, 7, item.lowStockThreshold)
        bindInt(stmt, 8, item.currentStock)
        bindOptDate(stmt, 9, item.lastRestockDate)
        bindBool(stmt, 10, item.isActive)
        bindOptInt(stmt, 11, item.salesCount)
        bindOptInt(stmt, 12, item.salesTier)
        bindOptText(stmt, 13, item.hsnCode)
        bindOptDouble(stmt, 14, item.gstRate)
        bindOptDouble(stmt, 15, item.cessRate)
        bindUUID(stmt, 16, item.id)
        sqlite3_step(stmt)
    }

    func deleteItem(id: UUID) throws {
        let sql = "DELETE FROM items WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        sqlite3_step(stmt)
    }


    func getBatches(for itemID: UUID) throws -> [ItemBatch] {
        let sql = "SELECT id,item_id,purchase_transaction_id,quantity_purchased,quantity_remaining,cost_price,selling_price,expiry_date,received_date FROM item_batches WHERE item_id=?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, itemID)
        var result: [ItemBatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readBatch(stmt)) }
        return result
    }

    func insertBatch(_ batch: ItemBatch) throws {
        let sql = "INSERT INTO item_batches (id,item_id,purchase_transaction_id,quantity_purchased,quantity_remaining,cost_price,selling_price,expiry_date,received_date) VALUES (?,?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, batch.id)
        bindUUID(stmt, 2, batch.itemID)
        bindUUID(stmt, 3, batch.purchaseTransactionID)
        bindInt(stmt, 4, batch.quantityPurchased)
        bindInt(stmt, 5, batch.quantityRemaining)
        bindDouble(stmt, 6, batch.costPrice)
        bindDouble(stmt, 7, batch.sellingPrice)
        bindOptDate(stmt, 8, batch.expiryDate)
        bindDate(stmt, 9, batch.receivedDate)
        sqlite3_step(stmt)
    }

    func updateBatch(_ batch: ItemBatch) throws {
        let sql = "UPDATE item_batches SET quantity_remaining=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindInt(stmt, 1, batch.quantityRemaining)
        bindUUID(stmt, 2, batch.id)
        sqlite3_step(stmt)
    }


    func insertTransaction(_ transaction: Transaction) throws {
        let sql = "INSERT INTO transactions (id,type,date,invoice_number,customer_name,customer_phone,supplier_name,total_amount,notes,buyer_gstin,place_of_supply,place_of_supply_code,is_inter_state,total_taxable_value,total_cgst,total_sgst,total_igst,total_cess,is_reverse_charge) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, transaction.id)
        bindText(stmt, 2, transaction.type.rawValue)
        bindDate(stmt, 3, transaction.date)
        bindText(stmt, 4, transaction.invoiceNumber)
        bindOptText(stmt, 5, transaction.customerName)
        bindOptText(stmt, 6, transaction.customerPhone)
        bindOptText(stmt, 7, transaction.supplierName)
        bindDouble(stmt, 8, transaction.totalAmount)
        bindOptText(stmt, 9, transaction.notes)
        bindOptText(stmt, 10, transaction.buyerGSTIN)
        bindOptText(stmt, 11, transaction.placeOfSupply)
        bindOptText(stmt, 12, transaction.placeOfSupplyCode)
        if let isInter = transaction.isInterState { bindBool(stmt, 13, isInter) } else { sqlite3_bind_null(stmt, 13) }
        bindOptDouble(stmt, 14, transaction.totalTaxableValue)
        bindOptDouble(stmt, 15, transaction.totalCGST)
        bindOptDouble(stmt, 16, transaction.totalSGST)
        bindOptDouble(stmt, 17, transaction.totalIGST)
        bindOptDouble(stmt, 18, transaction.totalCess)
        if let isRC = transaction.isReverseCharge { bindBool(stmt, 19, isRC) } else { sqlite3_bind_null(stmt, 19) }
        sqlite3_step(stmt)
    }

    func getTransactions() throws -> [Transaction] {
        let sql = "SELECT id,type,date,invoice_number,customer_name,customer_phone,supplier_name,total_amount,notes,buyer_gstin,place_of_supply,place_of_supply_code,is_inter_state,total_taxable_value,total_cgst,total_sgst,total_igst,total_cess,is_reverse_charge FROM transactions"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Transaction] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readTransaction(stmt)) }
        return result
    }


    func insertTransactionItems(_ items: [TransactionItem]) throws {
        let sql = "INSERT INTO transaction_items (id,transaction_id,item_id,item_name,unit,quantity,selling_price_per_unit,cost_price_per_unit,created_date,hsn_code,gst_rate,taxable_value,cgst_amount,sgst_amount,igst_amount,cess_amount) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        for item in items {
            sqlite3_reset(stmt)
            bindUUID(stmt, 1, item.id)
            bindUUID(stmt, 2, item.transactionID)
            bindUUID(stmt, 3, item.itemID)
            bindText(stmt, 4, item.itemName.capitalized)
            bindText(stmt, 5, item.unit)
            bindInt(stmt, 6, item.quantity)
            bindOptDouble(stmt, 7, item.sellingPricePerUnit)
            bindOptDouble(stmt, 8, item.costPricePerUnit)
            bindDate(stmt, 9, item.createdDate)
            bindOptText(stmt, 10, item.hsnCode)
            bindOptDouble(stmt, 11, item.gstRate)
            bindOptDouble(stmt, 12, item.taxableValue)
            bindOptDouble(stmt, 13, item.cgstAmount)
            bindOptDouble(stmt, 14, item.sgstAmount)
            bindOptDouble(stmt, 15, item.igstAmount)
            bindOptDouble(stmt, 16, item.cessAmount)
            sqlite3_step(stmt)
        }
    }

    func getTransactionItems(for transactionID: UUID) throws -> [TransactionItem] {
        let sql = "SELECT id,transaction_id,item_id,item_name,unit,quantity,selling_price_per_unit,cost_price_per_unit,created_date,hsn_code,gst_rate,taxable_value,cgst_amount,sgst_amount,igst_amount,cess_amount FROM transaction_items WHERE transaction_id=?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, transactionID)
        var result: [TransactionItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readTransactionItem(stmt)) }
        return result
    }

    func getTransactionItem(id: UUID) throws -> TransactionItem? {
        let sql = "SELECT id,transaction_id,item_id,item_name,unit,quantity,selling_price_per_unit,cost_price_per_unit,created_date,hsn_code,gst_rate,taxable_value,cgst_amount,sgst_amount,igst_amount,cess_amount FROM transaction_items WHERE id=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readTransactionItem(stmt) : nil
    }

    func updateTransactionItem(_ item: TransactionItem) throws {
        let sql = "UPDATE transaction_items SET item_id=?,item_name=?,unit=?,quantity=?,selling_price_per_unit=?,cost_price_per_unit=?,hsn_code=?,gst_rate=?,taxable_value=?,cgst_amount=?,sgst_amount=?,igst_amount=?,cess_amount=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, item.itemID)
        bindText(stmt, 2, item.itemName.capitalized)
        bindText(stmt, 3, item.unit)
        bindInt(stmt, 4, item.quantity)
        bindOptDouble(stmt, 5, item.sellingPricePerUnit)
        bindOptDouble(stmt, 6, item.costPricePerUnit)
        bindOptText(stmt, 7, item.hsnCode)
        bindOptDouble(stmt, 8, item.gstRate)
        bindOptDouble(stmt, 9, item.taxableValue)
        bindOptDouble(stmt, 10, item.cgstAmount)
        bindOptDouble(stmt, 11, item.sgstAmount)
        bindOptDouble(stmt, 12, item.igstAmount)
        bindOptDouble(stmt, 13, item.cessAmount)
        bindUUID(stmt, 14, item.id)
        sqlite3_step(stmt)
    }


    func insertSaleItemBatches(_ batches: [SaleItemBatch]) throws {
        let sql = "INSERT INTO sale_item_batches (id,transaction_item_id,batch_id,quantity_consumed,cost_price_used,selling_price_used,batch_received_date,batch_expiry_date) VALUES (?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        for b in batches {
            sqlite3_reset(stmt)
            bindUUID(stmt, 1, b.id)
            bindUUID(stmt, 2, b.transactionItemID)
            bindUUID(stmt, 3, b.batchID)
            bindInt(stmt, 4, b.quantityConsumed)
            bindDouble(stmt, 5, b.costPriceUsed)
            bindDouble(stmt, 6, b.sellingPriceUsed)
            bindDate(stmt, 7, b.batchReceivedDate)
            bindOptDate(stmt, 8, b.batchExpiryDate)
            sqlite3_step(stmt)
        }
    }

    func getSaleItemBatches(for transactionItemID: UUID) throws -> [SaleItemBatch] {
        let sql = "SELECT id,transaction_item_id,batch_id,quantity_consumed,cost_price_used,selling_price_used,batch_received_date,batch_expiry_date FROM sale_item_batches WHERE transaction_item_id=?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, transactionItemID)
        var result: [SaleItemBatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readSaleItemBatch(stmt)) }
        return result
    }


    func insertIncompleteSaleItem(_ item: IncompleteSaleItem) throws {
        let sql = "INSERT INTO incomplete_sale_items (id,transaction_id,transaction_item_id,item_name,quantity,selling_price_per_unit,is_completed,completed_at,unit,cost_price_per_unit,supplier_name,expiry_date,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, item.id)
        bindUUID(stmt, 2, item.transactionID)
        bindUUID(stmt, 3, item.transactionItemID)
        bindText(stmt, 4, item.itemName.capitalized)
        bindInt(stmt, 5, item.quantity)
        bindDouble(stmt, 6, item.sellingPricePerUnit)
        bindBool(stmt, 7, item.isCompleted)
        bindOptDate(stmt, 8, item.completedAt)
        bindOptText(stmt, 9, item.unit)
        bindOptDouble(stmt, 10, item.costPricePerUnit)
        bindOptText(stmt, 11, item.supplierName)
        bindOptDate(stmt, 12, item.expiryDate)
        bindDate(stmt, 13, item.createdAt)
        sqlite3_step(stmt)
    }

    func getIncompleteSaleItem(id: UUID) throws -> IncompleteSaleItem? {
        let sql = "SELECT id,transaction_id,transaction_item_id,item_name,quantity,selling_price_per_unit,is_completed,completed_at,unit,cost_price_per_unit,supplier_name,expiry_date,created_at FROM incomplete_sale_items WHERE id=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readIncompleteSaleItem(stmt) : nil
    }

    func getIncompleteSaleItems(completed: Bool?) throws -> [IncompleteSaleItem] {
        let sql: String
        if let c = completed {
            sql = "SELECT id,transaction_id,transaction_item_id,item_name,quantity,selling_price_per_unit,is_completed,completed_at,unit,cost_price_per_unit,supplier_name,expiry_date,created_at FROM incomplete_sale_items WHERE is_completed=?"
            guard let stmt = prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindBool(stmt, 1, c)
            var result: [IncompleteSaleItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(readIncompleteSaleItem(stmt)) }
            return result
        } else {
            sql = "SELECT id,transaction_id,transaction_item_id,item_name,quantity,selling_price_per_unit,is_completed,completed_at,unit,cost_price_per_unit,supplier_name,expiry_date,created_at FROM incomplete_sale_items"
            guard let stmt = prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var result: [IncompleteSaleItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(readIncompleteSaleItem(stmt)) }
            return result
        }
    }

    func updateIncompleteSaleItem(_ item: IncompleteSaleItem) throws {
        let sql = "UPDATE incomplete_sale_items SET is_completed=?,completed_at=?,unit=?,cost_price_per_unit=?,supplier_name=?,expiry_date=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindBool(stmt, 1, item.isCompleted)
        bindOptDate(stmt, 2, item.completedAt)
        bindOptText(stmt, 3, item.unit)
        bindOptDouble(stmt, 4, item.costPricePerUnit)
        bindOptText(stmt, 5, item.supplierName)
        bindOptDate(stmt, 6, item.expiryDate)
        bindUUID(stmt, 7, item.id)
        sqlite3_step(stmt)
    }


    func getDailySummary(for date: Date) throws -> DailySummary? {
        let dayStr = Self.dayString(date)
        let sql = "SELECT id,date,total_revenue,total_profit,sales_transaction_count,items_sold_count,total_purchase_amount,purchase_transaction_count FROM daily_summaries WHERE date=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, dayStr)
        return sqlite3_step(stmt) == SQLITE_ROW ? readDailySummary(stmt) : nil
    }

    func upsertDailySummary(_ summary: DailySummary) throws {
        let dayStr = Self.dayString(summary.date)
        let sql = """
        INSERT INTO daily_summaries (id,date,total_revenue,total_profit,sales_transaction_count,items_sold_count,total_purchase_amount,purchase_transaction_count)
        VALUES (?,?,?,?,?,?,?,?)
        ON CONFLICT(date) DO UPDATE SET
            total_revenue=excluded.total_revenue,
            total_profit=excluded.total_profit,
            sales_transaction_count=excluded.sales_transaction_count,
            items_sold_count=excluded.items_sold_count,
            total_purchase_amount=excluded.total_purchase_amount,
            purchase_transaction_count=excluded.purchase_transaction_count
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, summary.id)
        bindText(stmt, 2, dayStr)
        bindDouble(stmt, 3, summary.totalRevenue)
        bindDouble(stmt, 4, summary.totalProfit)
        bindInt(stmt, 5, summary.salesTransactionCount)
        bindInt(stmt, 6, summary.itemsSoldCount)
        bindDouble(stmt, 7, summary.totalPurchaseAmount)
        bindInt(stmt, 8, summary.purchaseTransactionCount)
        sqlite3_step(stmt)
    }

    private static func dayString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = Calendar.current.timeZone
        return df.string(from: date)
    }


    func getSettings() throws -> AppSettings {
        let sql = "SELECT invoice_prefix,invoice_number_counter,current_year,include_year_in_invoice,owner_name,business_name,profile_name,business_phone,profile_image_data,business_address,gst_number,expiry_notice_days,expiry_warning_days,expiry_critical_days,is_gst_registered,gst_scheme,business_state,business_state_code,prices_include_gst,default_gst_rate,composition_rate FROM app_settings WHERE key='main'"
        guard let stmt = prepare(sql) else { return defaultSettings() }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return readSettings(stmt)
        }
        let defaults = defaultSettings()
        try updateSettings(defaults)
        return defaults
    }

    func updateSettings(_ settings: AppSettings) throws {
        let sql = """
        INSERT INTO app_settings (key,invoice_prefix,invoice_number_counter,current_year,include_year_in_invoice,owner_name,business_name,profile_name,business_phone,profile_image_data,business_address,gst_number,expiry_notice_days,expiry_warning_days,expiry_critical_days,is_gst_registered,gst_scheme,business_state,business_state_code,prices_include_gst,default_gst_rate,composition_rate)
        VALUES ('main',?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(key) DO UPDATE SET
            invoice_prefix=excluded.invoice_prefix,
            invoice_number_counter=excluded.invoice_number_counter,
            current_year=excluded.current_year,
            include_year_in_invoice=excluded.include_year_in_invoice,
            owner_name=excluded.owner_name,
            business_name=excluded.business_name,
            profile_name=excluded.profile_name,
            business_phone=excluded.business_phone,
            profile_image_data=excluded.profile_image_data,
            business_address=excluded.business_address,
            gst_number=excluded.gst_number,
            expiry_notice_days=excluded.expiry_notice_days,
            expiry_warning_days=excluded.expiry_warning_days,
            expiry_critical_days=excluded.expiry_critical_days,
            is_gst_registered=excluded.is_gst_registered,
            gst_scheme=excluded.gst_scheme,
            business_state=excluded.business_state,
            business_state_code=excluded.business_state_code,
            prices_include_gst=excluded.prices_include_gst,
            default_gst_rate=excluded.default_gst_rate,
            composition_rate=excluded.composition_rate
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, settings.invoicePrefix)
        bindInt(stmt, 2, settings.invoiceNumberCounter)
        bindOptInt(stmt, 3, settings.currentYear)
        bindBool(stmt, 4, settings.includeYearInInvoice)
        bindOptText(stmt, 5, settings.ownerName)
        bindText(stmt, 6, settings.businessName)
        bindOptText(stmt, 7, settings.profileName)
        bindOptText(stmt, 8, settings.businessPhone)
        bindBlob(stmt, 9, settings.profileImageData)
        bindOptText(stmt, 10, settings.businessAddress)
        bindOptText(stmt, 11, settings.gstNumber)
        bindInt(stmt, 12, settings.expiryNoticeDays)
        bindInt(stmt, 13, settings.expiryWarningDays)
        bindInt(stmt, 14, settings.expiryCriticalDays)
        bindBool(stmt, 15, settings.isGSTRegistered)
        bindOptText(stmt, 16, settings.gstScheme)
        bindOptText(stmt, 17, settings.businessState)
        bindOptText(stmt, 18, settings.businessStateCode)
        bindBool(stmt, 19, settings.pricesIncludeGST)
        bindOptDouble(stmt, 20, settings.defaultGSTRate)
        bindOptDouble(stmt, 21, settings.compositionRate)
        sqlite3_step(stmt)
    }

    private func defaultSettings() -> AppSettings {
        AppSettings(
            invoicePrefix: "INV",
            invoiceNumberCounter: 1,
            currentYear: Calendar.current.component(.year, from: Date()),
            includeYearInInvoice: false,
            ownerName: nil,
            businessName: "My Shop",
            profileName: nil,
            businessPhone: nil,
            businessAddress: nil,
            gstNumber: nil,
            expiryNoticeDays: 14,
            expiryWarningDays: 7,
            expiryCriticalDays: 3
        )
    }


    func insertProductPhoto(_ photo: ProductPhoto) throws {
        let sql = "INSERT INTO product_photos (id,item_id,local_path,created_at) VALUES (?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, photo.id)
        bindUUID(stmt, 2, photo.itemID)
        bindText(stmt, 3, photo.localPath)
        bindDate(stmt, 4, photo.createdAt)
        sqlite3_step(stmt)
    }

    func getProductPhotos(for itemID: UUID) throws -> [ProductPhoto] {
        let sql = "SELECT id,item_id,local_path,created_at FROM product_photos WHERE item_id=?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, itemID)
        var result: [ProductPhoto] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readProductPhoto(stmt)) }
        return result
    }

    func deleteProductPhoto(id: UUID) throws {
        let sql = "DELETE FROM product_photos WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        sqlite3_step(stmt)
    }


    func insertCustomer(_ customer: Customer) {
        let sql = "INSERT INTO customers (id,name,phone,profile_image_data) VALUES (?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, customer.id)
        bindText(stmt, 2, customer.name)
        bindOptText(stmt, 3, customer.phone)
        bindBlob(stmt, 4, customer.profileImageData)
        sqlite3_step(stmt)
    }

    func updateCustomerRecord(_ customer: Customer) {
        let sql = "UPDATE customers SET name=?,phone=?,profile_image_data=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, customer.name)
        bindOptText(stmt, 2, customer.phone)
        bindBlob(stmt, 3, customer.profileImageData)
        bindUUID(stmt, 4, customer.id)
        sqlite3_step(stmt)
    }

    func deleteCustomerCascade(id: UUID) {
        exec("DELETE FROM customer_payments WHERE customer_id='\(id.uuidString)'")
        exec("DELETE FROM customers WHERE id='\(id.uuidString)'")
    }

    func getCustomerByID(_ id: UUID) -> Customer? {
        let sql = "SELECT id,name,phone,profile_image_data FROM customers WHERE id=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readCustomer(stmt) : nil
    }

    func getAllCustomers() -> [Customer] {
        let sql = "SELECT id,name,phone,profile_image_data FROM customers"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Customer] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readCustomer(stmt)) }
        return result
    }


    func insertSupplier(_ supplier: Supplier) {
        let sql = "INSERT INTO suppliers (id,name,phone,profile_image_data) VALUES (?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, supplier.id)
        bindText(stmt, 2, supplier.name)
        bindOptText(stmt, 3, supplier.phone)
        bindBlob(stmt, 4, supplier.profileImageData)
        sqlite3_step(stmt)
    }

    func updateSupplierRecord(_ supplier: Supplier) {
        let sql = "UPDATE suppliers SET name=?,phone=?,profile_image_data=? WHERE id=?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, supplier.name)
        bindOptText(stmt, 2, supplier.phone)
        bindBlob(stmt, 3, supplier.profileImageData)
        bindUUID(stmt, 4, supplier.id)
        sqlite3_step(stmt)
    }

    func deleteSupplierCascade(id: UUID) {
        exec("DELETE FROM supplier_payments WHERE supplier_id='\(id.uuidString)'")
        exec("DELETE FROM suppliers WHERE id='\(id.uuidString)'")
    }

    func getSupplierByID(_ id: UUID) -> Supplier? {
        let sql = "SELECT id,name,phone,profile_image_data FROM suppliers WHERE id=?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readSupplier(stmt) : nil
    }

    func getAllSuppliersFromDB() -> [Supplier] {
        let sql = "SELECT id,name,phone,profile_image_data FROM suppliers"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Supplier] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readSupplier(stmt)) }
        return result
    }


    func insertCustomerPayment(_ payment: Payment) {
        let sql = "INSERT INTO customer_payments (id,customer_id,amount,date,type,note) VALUES (?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, payment.id)
        bindUUID(stmt, 2, payment.customerID)
        bindDouble(stmt, 3, payment.amount)
        bindDate(stmt, 4, payment.date)
        bindText(stmt, 5, payment.type.rawValue)
        bindOptText(stmt, 6, payment.note)
        sqlite3_step(stmt)
    }

    func getCustomerPayments(forCustomer customerID: UUID) -> [Payment] {
        let sql = "SELECT id,customer_id,amount,date,type,note FROM customer_payments WHERE customer_id=? ORDER BY date ASC"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, customerID)
        var result: [Payment] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readPayment(stmt)) }
        return result
    }

    func insertSupplierPaymentRecord(_ payment: SupplierPayment) {
        let sql = "INSERT INTO supplier_payments (id,supplier_id,amount,date,type,note) VALUES (?,?,?,?,?,?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, payment.id)
        bindUUID(stmt, 2, payment.supplierID)
        bindDouble(stmt, 3, payment.amount)
        bindDate(stmt, 4, payment.date)
        bindText(stmt, 5, payment.type.rawValue)
        bindOptText(stmt, 6, payment.note)
        sqlite3_step(stmt)
    }

    func getSupplierPayments(forSupplier supplierID: UUID) -> [SupplierPayment] {
        let sql = "SELECT id,supplier_id,amount,date,type,note FROM supplier_payments WHERE supplier_id=? ORDER BY date ASC"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, 1, supplierID)
        var result: [SupplierPayment] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(readSupplierPayment(stmt)) }
        return result
    }


    var isEmpty: Bool {
        let sql = "SELECT COUNT(*) FROM items"
        guard let stmt = prepare(sql) else { return true }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? readInt(stmt, 0) == 0 : true
    }

    func clearAllPersistedData() {
        let tables = [
            "sale_item_batches", "transaction_items", "item_batches",
            "incomplete_sale_items", "product_photos", "transactions",
            "daily_summaries", "items", "app_settings",
            "customer_payments", "supplier_payments", "customers", "suppliers"
        ]
        exec("BEGIN TRANSACTION")
        for t in tables { exec("DELETE FROM \(t)") }
        exec("COMMIT")
    }

    func reopenDatabase() {
        sqlite3_close(db)
        db = nil
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            exec("PRAGMA journal_mode=WAL")
            exec("PRAGMA foreign_keys=ON")
        }
    }

    func backupDatabase(to destinationPath: String) -> Bool {
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_FULL, nil, nil)

        var destDB: OpaquePointer?
        guard sqlite3_open(destinationPath, &destDB) == SQLITE_OK else { return false }
        defer { sqlite3_close(destDB) }

        guard let backup = sqlite3_backup_init(destDB, "main", db, "main") else {
            return false
        }

        sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)

        return sqlite3_errcode(destDB) == SQLITE_OK
    }
}
