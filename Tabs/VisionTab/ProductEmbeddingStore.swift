//  SQLite storage for product feature vectors (CLIP 512-dim).
//  Stores INDIVIDUAL embeddings per photo (not averaged) for better matching accuracy.
//  Matching uses max(cosine_sim) across all stored embeddings per item.

import Foundation
import SQLite3
import Accelerate

final class ProductEmbeddingStore {

    static let shared = ProductEmbeddingStore()
     var db: OpaquePointer?
     let queue = DispatchQueue(label: "ProductEmbeddingStore.queue")

    /// Preferred dimension: CLIP = 512.
    static var embeddingDimension: Int {
        FeatureExtractorProvider.vectorExtractor?.dimension ?? 512
    }

     init() {}

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

     func ensureDb() {
        guard db == nil else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tabsData = docs.appendingPathComponent("TabsData", isDirectory: true)
        try? FileManager.default.createDirectory(at: tabsData, withIntermediateDirectories: true)
        let path = tabsData.appendingPathComponent("product_embeddings.sqlite").path
        var localDb: OpaquePointer?
        if sqlite3_open_v2(path, &localDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK {
            db = localDb
            migrateToMultiEmbedding()
        }
    }

    // MARK: - Schema Migration

    /// Migrate from single-embedding (PRIMARY KEY on item_id) to multi-embedding table.
  
     func migrateToMultiEmbedding() {
        let createV2 = """
        CREATE TABLE IF NOT EXISTS product_embeddings_v2 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id TEXT NOT NULL,
            embedding_blob BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_embeddings_item ON product_embeddings_v2(item_id);
        """
        executeStatements(createV2)

        // Migrate data from old table if it exists
        let checkOld = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='product_embeddings';"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, checkOld, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW,
           sqlite3_column_int(stmt, 0) > 0 {
            // Old table exists — migrate its data then drop it
            let migrate = """
            INSERT INTO product_embeddings_v2 (item_id, embedding_blob, updated_at)
            SELECT item_id, embedding_blob, updated_at FROM product_embeddings
            WHERE item_id NOT IN (SELECT DISTINCT item_id FROM product_embeddings_v2);
            DROP TABLE product_embeddings;
            """
            executeStatements(migrate)
        }
    }

     func executeStatements(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &errMsg)
        if let err = errMsg {
            let msg = String(cString: err)
            if !msg.contains("already exists") {
            }
            sqlite3_free(err)
        }
    }

    // MARK: - Insert Individual Embeddings

    /// Insert a single embedding for an item (one per photo). Call multiple times for multiple photos.
    func insertEmbedding(itemID: UUID, embedding: [Float]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureDb()
            guard let db = self.db else { return }
            let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            let now = Date().timeIntervalSince1970
            let idStr = itemID.uuidString
            let sql = "INSERT INTO product_embeddings_v2 (item_id, embedding_blob, updated_at) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            data.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_step(stmt)
        }
    }

    /// Replace all embeddings for an item (delete old, insert new batch).
    func replaceEmbeddings(itemID: UUID, embeddings: [[Float]]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureDb()
            guard let db = self.db else { return }
            let idStr = itemID.uuidString
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

            // Delete existing
            let delSql = "DELETE FROM product_embeddings_v2 WHERE item_id = ?;"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delSql, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)

            // Insert all new
            let now = Date().timeIntervalSince1970
            let insSql = "INSERT INTO product_embeddings_v2 (item_id, embedding_blob, updated_at) VALUES (?, ?, ?);"
            for embedding in embeddings {
                let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
                var insStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, insSql, -1, &insStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(insStmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    data.withUnsafeBytes { ptr in sqlite3_bind_blob(insStmt, 2, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
                    sqlite3_bind_double(insStmt, 3, now)
                    sqlite3_step(insStmt)
                }
                sqlite3_finalize(insStmt)
            }
        }
    }

    /// Keep backward-compatible API for any callers that still use the old signature.
    func upsertEmbedding(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]? = nil, geometricFeatures: [Float]? = nil) {
        replaceEmbeddings(itemID: itemID, embeddings: [embedding])
    }

    // MARK: - Load All Embeddings

    /// Load all embeddings — returns multiple rows per item (one per photo).
    func loadAllEmbeddings() -> [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)] {
        var result: [(itemID: UUID, embedding: [Float], sampleCount: Int, colorHistogram: [Float]?, geometricFeatures: [Float]?)] = []
        queue.sync {
            ensureDb()
            guard let db = db else { return }
            let sql = "SELECT item_id, embedding_blob FROM product_embeddings_v2;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(stmt, 0),
                      let uuid = UUID(uuidString: String(cString: idPtr)) else { continue }
                guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
                let blobLen = Int(sqlite3_column_bytes(stmt, 1))
                let floats = blobPtr.withMemoryRebound(to: Float.self, capacity: blobLen / MemoryLayout<Float>.size) { ptr in
                    Array(UnsafeBufferPointer(start: ptr, count: blobLen / MemoryLayout<Float>.size))
                }
                // sampleCount=1 per row (individual embedding), color/geo = nil
                result.append((itemID: uuid, embedding: floats, sampleCount: 1, colorHistogram: nil, geometricFeatures: nil))
            }
        }
        return result
    }

    // MARK: - Delete

    /// Remove all embeddings when item or photos are deleted.
    func deleteEmbedding(itemID: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureDb()
            guard let db = self.db else { return }
            let sql = "DELETE FROM product_embeddings_v2 WHERE item_id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let idStr = itemID.uuidString
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Cosine Similarity

    /// Cosine similarity between two vectors — Accelerate vDSP vectorized.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(n))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(n))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(n))
        let denom = sqrtf(normA) * sqrtf(normB)
        return denom > 0 ? dot / denom : 0
    }
}
