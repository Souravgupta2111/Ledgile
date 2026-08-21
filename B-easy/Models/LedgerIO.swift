import Foundation

nonisolated enum LedgerIO {
    static let queue = DispatchQueue(label: "com.beasy.ledger.io", qos: .userInitiated)

    static func run<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            do {
                let value = try work()
                DispatchQueue.main.async { completion(.success(value)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
