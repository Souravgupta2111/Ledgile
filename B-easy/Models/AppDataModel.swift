import Foundation
nonisolated class AppDataModel: @unchecked Sendable {

    static let shared = AppDataModel()

    let dataModel: DataModel

     init() {
        let db = SQLiteDatabase.shared
        dataModel = DataModel(database: db)
    }
}

