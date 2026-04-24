import Foundation

/// Free barcode-to-product lookup via Open Food Facts (openfoodfacts.org).
/// No API key required. No cost. 3M+ products worldwide.
final class OpenFoodFactsService {

    static let shared = OpenFoodFactsService()
    private init() {}

    struct ProductInfo {
        let name: String
        let brand: String?
        let category: String?
        let quantity: String?       // e.g., "70g", "500ml"
        let imageURL: String?
    }

    /// Look up a barcode in the Open Food Facts database.
    /// Returns nil if the product is not found or the network fails.
    func lookupBarcode(_ barcode: String, completion: @escaping (ProductInfo?) -> Void) {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Ledgile iOS App - contact@ledgile.app", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
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
                    ?? product["generic_name"] as? String

                guard let productName = name, !productName.isEmpty else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let brand = product["brands"] as? String
                let category = product["categories"] as? String
                let quantity = product["quantity"] as? String
                let imageURL = product["image_front_small_url"] as? String

                let info = ProductInfo(
                    name: productName,
                    brand: brand,
                    category: category,
                    quantity: quantity,
                    imageURL: imageURL
                )

                DispatchQueue.main.async { completion(info) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
