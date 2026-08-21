import Foundation
import StoreKit

@MainActor
final class ProStore {

    static let shared = ProStore()

    private(set) var monthlyProduct: StoreKit.Product?
    private(set) var yearlyProduct: StoreKit.Product?
    private var updatesTask: Task<Void, Never>?

    private init() {}

    func start() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let ids: Set<String> = [
                UsageTracker.monthlyProductID,
                UsageTracker.yearlyProductID
            ]
            let products = try await StoreKit.Product.products(for: ids)
            monthlyProduct = products.first { $0.id == UsageTracker.monthlyProductID }
            yearlyProduct = products.first { $0.id == UsageTracker.yearlyProductID }
        } catch {
            print("[ProStore] Failed to load products: \(error)")
        }
        await updateEntitlement()
    }

    func purchase(_ product: StoreKit.Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            await handle(verification)
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await updateEntitlement()
    }

    var displayMonthlyPrice: String {
        monthlyProduct?.displayPrice ?? "₹\(UsageTracker.monthlyPriceINR)"
    }

    var displayYearlyPrice: String {
        yearlyProduct?.displayPrice ?? "₹\(UsageTracker.yearlyPriceINR)"
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await updateEntitlement()
        await transaction.finish()
    }

    private func updateEntitlement() async {
        var entitled = false
        var entitledJWS: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == UsageTracker.monthlyProductID
                || transaction.productID == UsageTracker.yearlyProductID {
                if transaction.revocationDate == nil {
                    entitled = true
                    entitledJWS = result.jwsRepresentation
                    break
                }
            }
        }
        UsageTracker.shared.setStoreKitEntitled(entitled)
        if entitled, let jws = entitledJWS {
            GeminiService.shared.syncProEntitlement(jws: jws)
        }
    }
}
