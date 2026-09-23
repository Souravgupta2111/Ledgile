import Foundation


final class GlobalCatalogService {

    static let shared = GlobalCatalogService()

    // MARK: - Configuration

    private let supabaseURL: String = {
        Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    }()

    private let supabaseAnonKey: String = {
        Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
    }()

    private let session = URLSession.shared
    private let tableName = "global_products"

    private init() {}


    struct CatalogProduct {
        let name: String
        let unit: String
        let category: String?
        let defaultCostPrice: Double?
        let defaultSellingPrice: Double?
        let barcode: String?
    }

    var isConfigured: Bool {
        let authConfigured = AuthManager.shared.isConfigured
        return authConfigured
    }


    func search(query: String, limit: Int = 10, completion: @escaping ([CatalogProduct]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isConfigured else {
            DispatchQueue.main.async { completion([]) }
            return
        }


        let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = "\(supabaseURL)/rest/v1/\(tableName)?name=ilike.\(encodedQuery)%25&limit=\(limit)&select=name,unit,category,default_cost_price,default_selling_price,barcode"

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5  // Fast timeout for autocomplete

        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data = data,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let products = jsonArray.compactMap { dict -> CatalogProduct? in
                guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
                return CatalogProduct(
                    name: name,
                    unit: dict["unit"] as? String ?? "pcs",
                    category: dict["category"] as? String,
                    defaultCostPrice: dict["default_cost_price"] as? Double,
                    defaultSellingPrice: dict["default_selling_price"] as? Double,
                    barcode: dict["barcode"] as? String
                )
            }

            print("[GlobalCatalog] Query '\(trimmed)' → \(products.count) results")
            DispatchQueue.main.async { completion(products) }
        }.resume()
    }


    private var currentTask: URLSessionDataTask?

    func debouncedSearch(query: String, limit: Int = 10, completion: @escaping ([CatalogProduct]) -> Void) {
        // Cancel any in-flight request before starting a new one
        currentTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isConfigured else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = "\(supabaseURL)/rest/v1/\(tableName)?name=ilike.\(encodedQuery)%25&limit=\(limit)&select=name,unit,category,default_cost_price,default_selling_price,barcode"

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        let task = session.dataTask(with: request) { data, response, error in
            // Ignore cancelled tasks 
            if let urlError = error as? URLError, urlError.code == .cancelled { return }

            guard error == nil,
                  let data = data,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let products = jsonArray.compactMap { dict -> CatalogProduct? in
                guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
                return CatalogProduct(
                    name: name,
                    unit: dict["unit"] as? String ?? "pcs",
                    category: dict["category"] as? String,
                    defaultCostPrice: dict["default_cost_price"] as? Double,
                    defaultSellingPrice: dict["default_selling_price"] as? Double,
                    barcode: dict["barcode"] as? String
                )
            }

            DispatchQueue.main.async { completion(products) }
        }

        currentTask = task
        task.resume()
    }
}
