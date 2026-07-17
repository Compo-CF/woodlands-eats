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
    /// v2.1: three consumable "tip jar" products — the App Store 3.1.1-
    /// compliant way to let users support the app (replaces the removed
    /// external Ko-fi link). Ordered small → generous; displayed with
    /// StoreKit's localized price so we never hard-code dollar amounts.
    private let tipProductIDs = [
        "com.compofelice.WoodlandsEats.tip.small",
        "com.compofelice.WoodlandsEats.tip.medium",
        "com.compofelice.WoodlandsEats.tip.large",
    ]

    /// v2.1: set true briefly after a successful tip so the UI can show a
    /// thank-you. The view flips it back to false when the message is shown.
    var didTip: Bool = false

    /// v2.1: whether the user has ever tipped (persisted). Once true, the
    /// occasional tip reminder never fires again — we don't nag supporters.
    private(set) var hasEverTipped: Bool = false

    // Tip-reminder cadence keys. The reminder is deliberately rare: nothing
    // for the first 2 weeks after install, then at most once every 60 days,
    // and never after the user tips or taps "Don't ask again."
    private let everTippedKey = "WoodlandsEats.iap.hasEverTipped"
    private let tipNeverAskKey = "WoodlandsEats.tip.neverAsk"
    private let tipLastPromptKey = "WoodlandsEats.tip.lastPromptAt"   // epoch seconds
    private let tipInstallDateKey = "WoodlandsEats.tip.firstSeenAt"   // epoch seconds
    private let graceDays: Double = 14
    private let betweenPromptDays: Double = 60
    /// @ObservationIgnored because @Observable's macro-generated tracking
    /// code accesses property storage from contexts the compiler can't
    /// prove are MainActor-isolated. We never read this from views (it's
    /// fire-and-forget cleanup state), so opting out of observation is
    /// both safe and required under Swift 6 strict concurrency.
    @ObservationIgnored
    private var updateListenerTask: Task<Void, Never>?

    init() {
        // Restore cached state synchronously — StoreKit fetches are
        // async and we don't want a brief "ad showing" flash on launch
        // before entitlements resolve. The async updateEntitlements()
        // run below corrects the cache if it disagrees with Apple.
        isAdFree = UserDefaults.standard.bool(forKey: isAdFreeKey)
        hasEverTipped = UserDefaults.standard.bool(forKey: everTippedKey)
        // Stamp first-seen once so the reminder's 2-week grace has a baseline.
        if UserDefaults.standard.object(forKey: tipInstallDateKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tipInstallDateKey)
        }

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

    // No deinit: PurchaseStore is held in @State at the app root and
    // lives for the entire app lifetime. The updateListenerTask gets
    // cleaned up by the system at process exit. (Also: @MainActor-
    // isolated properties can't be read from a nonisolated deinit
    // under Swift 6 strict concurrency, so even if we wanted to
    // .cancel() it here, the compiler would reject it.)

    /// Convenience accessor — the "Remove Ads" product, or nil if it
    /// hasn't loaded yet (or doesn't exist in App Store Connect).
    var adFreeProduct: Product? {
        products.first { $0.id == adFreeProductID }
    }

    /// v2.1: the tip products, small → generous (by price). Empty until
    /// loaded / if the IAPs don't exist in App Store Connect yet.
    var tipProducts: [Product] {
        products.filter { tipProductIDs.contains($0.id) }
            .sorted { $0.price < $1.price }
    }

    /// Fetch product metadata from App Store Connect. Called on init.
    /// Errors are logged; the UI gracefully degrades to disabled button.
    func loadProducts() async {
        do {
            self.products = try await Product.products(for: [adFreeProductID] + tipProductIDs)
        } catch {
            print("[Purchase] loadProducts failed: \(error)")
        }
    }

    /// v2.1: purchase a consumable tip. No entitlement to track — just
    /// complete the transaction, finish it, and flag the thank-you.
    func purchaseTip(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(.verified(let transaction)) = result {
                await transaction.finish()
                didTip = true
                hasEverTipped = true
                UserDefaults.standard.set(true, forKey: everTippedKey)
            }
        } catch {
            print("[Purchase] tip failed: \(error)")
        }
    }

    // MARK: - Occasional tip reminder (v2.1)

    /// Whether it's OK to surface the gentle tip reminder on this launch.
    /// False if: opted out, already tipped, products not loaded, still in the
    /// 2-week grace after install, or fewer than 60 days since the last prompt.
    var tipReminderEligible: Bool {
        let d = UserDefaults.standard
        guard !d.bool(forKey: tipNeverAskKey), !hasEverTipped,
              !tipProducts.isEmpty, !isPurchasing else { return false }
        let now = Date().timeIntervalSince1970
        let firstSeen = d.double(forKey: tipInstallDateKey)
        guard firstSeen > 0, now - firstSeen >= graceDays * 86400 else { return false }
        let last = d.double(forKey: tipLastPromptKey)
        return last == 0 ? true : (now - last >= betweenPromptDays * 86400)
    }

    /// Call when the reminder is shown, to reset the 60-day clock.
    func recordTipPromptShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tipLastPromptKey)
    }

    /// "Don't ask again" — permanently silences the reminder.
    func stopTipReminders() {
        UserDefaults.standard.set(true, forKey: tipNeverAskKey)
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
