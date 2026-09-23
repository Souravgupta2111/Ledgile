import Foundation

/// Free barcode-to-product lookup via Open Food Facts (openfoodfacts.org).
/// No API key required. No cost. 3M+ products worldwide.
final class OpenFoodFactsService {

    static let shared = OpenFoodFactsService()
    private init() {}

    private var cache: [String: ProductInfo] = [:]
    private let cacheLock = NSLock()

    struct ProductInfo {
        let name: String
        let brand: String?
        let category: String?
        let quantity: String?       // e.g., "70g", "500ml", "1 kg"
        let imageURL: String?

        /// Clean display name combining brand and product name (e.g., "Nestlé Maggi 2-Minute Noodles")
        var displayName: String {
            guard let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty else {
                return name
            }
            if name.localizedCaseInsensitiveContains(brand) {
                return name
            }
            return "\(brand) \(name)"
        }

        /// Normalized unit matching B-easy unit choices (e.g., "pcs", "kg", "g", "ltr", "ml", "packet")
        var inferredUnit: String {
            guard let q = quantity?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return "pcs" }
            if q.contains("kg") { return "kg" }
            if q.contains("gm") || q.contains(" g") || q.hasSuffix("g") || q.contains("gram") { return "g" }
            if q.contains("ltr") || q.contains("liter") || q.contains("litre") || q.contains(" l") || q.hasSuffix("l") { return "ltr" }
            if q.contains("ml") { return "ml" }
            if q.contains("pack") || q.contains("pkt") || q.contains("pouch") { return "packet" }
            if q.contains("bottle") || q.contains("btl") { return "bottle" }
            if q.contains("can") { return "can" }
            if q.contains("box") { return "box" }
            return "pcs"
        }
    }

    /// Look up a barcode in the Open Food Facts database.
    /// Returns cached result immediately if available, otherwise queries openfoodfacts.org.
    func lookupBarcode(_ barcode: String, completion: @escaping (ProductInfo?) -> Void) {
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBarcode.isEmpty else {
            completion(nil)
            return
        }

        cacheLock.lock()
        if let cached = cache[cleanBarcode] {
            cacheLock.unlock()
            DispatchQueue.main.async { completion(cached) }
            return
        }
        cacheLock.unlock()

        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(cleanBarcode).json"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("Ledgile iOS App - contact@ledgile.app", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? Int, status == 1,
                      let product = json["product"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let name = product["product_name"] as? String
                    ?? product["product_name_en"] as? String
                    ?? product["product_name_hi"] as? String
                    ?? product["generic_name"] as? String

                guard let productName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let brand = (product["brands"] as? String ?? product["brand_owner"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let category = (product["categories"] as? String)?
                    .components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                let quantity = (product["quantity"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let imageURL = product["image_front_small_url"] as? String
                    ?? product["image_url"] as? String

                let info = ProductInfo(
                    name: productName,
                    brand: (brand?.isEmpty == false) ? brand : nil,
                    category: (category?.isEmpty == false) ? category : nil,
                    quantity: (quantity?.isEmpty == false) ? quantity : nil,
                    imageURL: imageURL
                )

                self.cacheLock.lock()
                self.cache[cleanBarcode] = info
                self.cacheLock.unlock()

                DispatchQueue.main.async { completion(info) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
