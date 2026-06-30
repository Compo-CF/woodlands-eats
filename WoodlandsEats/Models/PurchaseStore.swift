import Foundation
import StoreKit

/// v1.7 Feature D: In-app purchase store for the "Remove Ads" upgrade.
/// One-time non-consumable IAP at $1.99 — buy once, ad-free forever
/// across all the user's devices (StoreKit syncs entitlements via
/// Apple ID, no CloudKit/Firebase needed).
///
/// Decision: one-time vs subscription. Picked one-time because:
///   - Simpler UX ("buy once, done forever" matches user expectation)
///   - No recurring-billing edge cases (renewal, grace period, refund flow)
///   - No subscription-specific App Review questionnaire
///   - Subscription can be added later as a separate product if usage
///     warrants ongoing revenue.
///
/// App Store Connect setup the user must do manually before the next
/// review submission can include this feature:
///   - In-App Purchases → Create
///   - Type: Non-Consumable
///   - Reference Name: "Ad-Free Upgrade"
///   - Product ID: com.compofelice.WoodlandsEats.adfree
///   - Price: Tier 2 ($1.99 USD)
///   - Display Name: "Remove Ads"
///   - Description: "Remove banner ads from S-Tier Eats forever. One-
///     time purchase, no subscription."
///   - Review Screenshot: a screenshot of the Profile section showing
///     the Remove Ads button
///   - Status: "Ready to Submit" — gets reviewed alongside the binary
@MainActor
@Observable
final class PurchaseStore {
    /// Products fetched from App Store Connect on init. Empty if the
    /// IAP hasn't been created yet OR if the network call failed —
    /// caller checks `adFreeProduct` for nil before showing the
    /// purchase button.
    private(set) var products: [Product] = []

    /// Whether the current Apple ID owns the ad-free entitlement.
    /// Mirrored to UserDefaults so AdsService / view code can read
    /// synchronously without going through StoreKit on every check.
    private(set) var isAdFree: Bool = false

    /// True between a tap on "Remove Ads" and the purchase resolving
    /// (success / cancel / error). Used to disable the button so
    /// users can't double-tap.
    private(set) var isPurchasing: Bool = false

    private let adFreeProductID = "com.compofelice.WoodlandsEats.adfree"
    private let isAdFreeKey = "WoodlandsEats.iap.isAdFree"
    private var updateListenerTask: Task<Void, Never>?

    init() {
        // Restore cached state synchronously — StoreKit fetches are
        // async and we don't want a brief "ad showing" flash on launch
        // before entitlements resolve. The async updateEntitlements()
        // run below corrects the cache if it disagrees with Apple.
        isAdFree = UserDefaults.standard.bool(forKey: isAdFreeKey)

        // Listen for transaction updates that arrive outside our
        // purchase flow — refunds, family sharing, purchases on other
        // devices, App Store reload.
        updateListenerTask = Task { [weak self] in
            await self?.listenForTransactions()
        }

        Task { [weak self] in
            await self?.loadProducts()
            await self?.updateEntitlements()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    /// Convenience accessor — the "Remove Ads" product, or nil if it
    /// hasn't loaded yet (or doesn't exist in App Store Connect).
    var adFreeProduct: Product? {
        products.first { $0.id == adFreeProductID }
    }

    /// Fetch product metadata from App Store Connect. Called on init.
    /// Errors are logged; the UI gracefully degrades to disabled button.
    func loadProducts() async {
        do {
            self.products = try await Product.products(for: [adFreeProductID])
        } catch {
            print("[Purchase] loadProducts failed: \(error)")
        }
    }

    /// Kicks off the Apple purchase sheet for the ad-free upgrade.
    /// Updates `isAdFree` on verified success. No-op if the product
    /// hasn't loaded or a purchase is already in flight.
    func purchaseAdFree() async {
        guard let product = adFreeProduct, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(.verified(let transaction)) = result {
                setAdFree(true)
                await transaction.finish()
            }
        } catch {
            print("[Purchase] purchase failed: \(error)")
        }
    }

    /// Apple-required "Restore Purchases" affordance. Non-consumables
    /// already auto-restore on new devices via Apple ID sign-in, so
    /// this rarely matters in practice — but App Review will reject
    /// apps without it, and edge cases (multiple Apple IDs, restored
    /// from backup) make it occasionally useful.
    func restorePurchases() async {
        try? await AppStore.sync()
        await updateEntitlements()
    }

    /// Iterate over the user's current entitlements and set `isAdFree`
    /// based on whether the ad-free product appears. Handles revocation
    /// (refund, family-sharing removal) by clearing the flag if the
    /// entitlement disappears.
    func updateEntitlements() async {
        var adFree = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == adFreeProductID,
               transaction.revocationDate == nil {
                adFree = true
            }
        }
        setAdFree(adFree)
    }

    /// Persists the new value to UserDefaults so AdsService / view code
    /// can read it without re-entering an async chain.
    private func setAdFree(_ value: Bool) {
        isAdFree = value
        UserDefaults.standard.set(value, forKey: isAdFreeKey)
    }

    /// Long-running task that observes transaction updates from outside
    /// the purchase flow (e.g., a purchase made on another device while
    /// this one was running). Started in init, cancelled in deinit.
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == adFreeProductID {
                setAdFree(transaction.revocationDate == nil)
            }
            await transaction.finish()
        }
    }
}
