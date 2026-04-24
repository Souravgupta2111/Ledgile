import UIKit

// MARK: - Transaction Types
enum CreditTransactionType: String, Codable {
    case paid       // money given out (red)
    case received   // money received in (green)
}

// MARK: - Customer Payment
struct Payment: Identifiable, Codable, Equatable {
    let id: UUID
    let customerID: UUID
    var amount: Double
    var date: Date
    var type: CreditTransactionType
    var note: String?
    
    static func == (lhs: Payment, rhs: Payment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Customer
struct Customer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var phone: String?
    var profileImageData: Data?
    
    // Transient — not persisted, computed from transactions
    var netBalance: Double = 0
    
    enum CodingKeys: String, CodingKey {
        case id, name, phone, profileImageData
    }
    
    var profileImage: UIImage? {
        get {
            guard let data = profileImageData else { return nil }
            return UIImage(data: data)
        }
        set {
            profileImageData = newValue?.jpegData(compressionQuality: 0.7)
        }
    }
    
    static func == (lhs: Customer, rhs: Customer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supplier Payment
struct SupplierPayment: Identifiable, Codable, Equatable {
    let id: UUID
    let supplierID: UUID
    var amount: Double
    var date: Date
    var type: CreditTransactionType
    var note: String?
    
    static func == (lhs: SupplierPayment, rhs: SupplierPayment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supplier
struct Supplier: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var phone: String?
    var profileImageData: Data?
    
    // Transient — not persisted, computed from transactions
    var netBalance: Double = 0
    
    enum CodingKeys: String, CodingKey {
        case id, name, phone, profileImageData
    }
    
    var profileImage: UIImage? {
        get {
            guard let data = profileImageData else { return nil }
            return UIImage(data: data)
        }
        set {
            profileImageData = newValue?.jpegData(compressionQuality: 0.7)
        }
    }
    
    static func == (lhs: Supplier, rhs: Supplier) -> Bool {
        lhs.id == rhs.id
    }
}
