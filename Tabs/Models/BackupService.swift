import Foundation

final class BackupService {

    static let shared = BackupService()

    private init() {}

    // MARK: - Paths

    private var sqliteDB: SQLiteDatabase { SQLiteDatabase.shared }

    private var backupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = formatter.string(from: Date())
        return "LedgileBackup_\(dateStr).sqlite"
    }

    // MARK: - Public: Export Backup
    func createBackup() -> URL? {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let backupURL = tempDir.appendingPathComponent(backupFileName)

        // Remove any old backup with the same name
        try? fm.removeItem(at: backupURL)

        let success = sqliteDB.backupDatabase(to: backupURL.path)
        if success {
            print("[BackupService] SQLite backup created: \(backupURL.lastPathComponent)")
            return backupURL
        } else {
            print("[BackupService] SQLite backup failed")
            return nil
        }
    }

    func localDataSizeString() -> String {
        let dbPath = sqliteDB.dbPath
        let fm = FileManager.default

        var totalBytes: Int64 = 0

        // Main database file
        if let attrs = try? fm.attributesOfItem(atPath: dbPath),
           let size = attrs[.size] as? Int64 {
            totalBytes += size
        }

        // WAL file
        let walPath = dbPath + "-wal"
        if let attrs = try? fm.attributesOfItem(atPath: walPath),
           let size = attrs[.size] as? Int64 {
            totalBytes += size
        }

        // SHM file
        let shmPath = dbPath + "-shm"
        if let attrs = try? fm.attributesOfItem(atPath: shmPath),
           let size = attrs[.size] as? Int64 {
            totalBytes += size
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    // MARK: - Public: Restore Backup
        func restoreBackup(from sqliteURL: URL) -> Bool {
        let fm = FileManager.default
        let dbPath = sqliteDB.dbPath

        do {
            // Start accessing security scoped resource if needed
            let accessing = sqliteURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { sqliteURL.stopAccessingSecurityScopedResource() }
            }

            let backupData = try Data(contentsOf: sqliteURL)
            sqliteDB.reopenDatabase()
            try? fm.removeItem(atPath: dbPath)
            try? fm.removeItem(atPath: dbPath + "-wal")
            try? fm.removeItem(atPath: dbPath + "-shm")

            // Write the backup data as the new database
            try backupData.write(to: URL(fileURLWithPath: dbPath), options: .atomic)

            // Reopen the database connection
            sqliteDB.reopenDatabase()

            print("[BackupService] SQLite restore completed successfully.")
            return true

        } catch {
            print("[BackupService] Restore failed: \(error)")
            // Reopen whatever we have
            sqliteDB.reopenDatabase()
            return false
        }
    }

    // MARK: - iCloud Backup

    /// Upload the database backup to iCloud Documents container.
    func backupToiCloud(completion: @escaping (Bool, String) -> Void) {
        guard let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true) else {
            completion(false, "iCloud is not available. Please sign in to iCloud in Settings.")
            return
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: iCloudURL, withIntermediateDirectories: true)

        let destURL = iCloudURL.appendingPathComponent("ledgile_backup.sqlite")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Create a local backup first
            guard let localBackup = self.createBackup() else {
                DispatchQueue.main.async { completion(false, "Failed to create local backup.") }
                return
            }

            do {
                // Remove old iCloud backup if exists
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: localBackup, to: destURL)

                // Clean up local temp
                try? fm.removeItem(at: localBackup)

                DispatchQueue.main.async {
                    let df = DateFormatter()
                    df.dateStyle = .short
                    df.timeStyle = .short
                    completion(true, "Backed up at \(df.string(from: Date()))")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "iCloud upload failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Restore database from iCloud.
    func restoreFromiCloud(completion: @escaping (Bool, String) -> Void) {
        guard let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents")
                .appendingPathComponent("ledgile_backup.sqlite") else {
            completion(false, "iCloud is not available.")
            return
        }

        guard FileManager.default.fileExists(atPath: iCloudURL.path) else {
            completion(false, "No backup found in iCloud.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.restoreBackup(from: iCloudURL)
            DispatchQueue.main.async {
                if success {
                    completion(true, "Restored successfully from iCloud.")
                } else {
                    completion(false, "Failed to restore from iCloud backup.")
                }
            }
        }
    }
}
