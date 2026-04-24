import UIKit

struct PurchaseEntry {
    var selectedItemName: String? = nil
    var selectedItemID: UUID? = nil
    var selectedUnitName: String? = nil
    
    var quantity: Double = 0
    var sellingPrice: Double = 0
    var costPrice: Double = 0
    
    var lowStockThreshold: Int = 0
    var barcode: String? = nil
    
    // GST fields
    var hsnCode: String? = nil
    var gstRate: Double? = nil
    
    var pendingItemPhotos: [UIImage] = []
    var expiryDate: Date = Date()
}
