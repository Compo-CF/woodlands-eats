import SwiftUI
import StoreKit

/// v3.0: the S-Tier Plus paywall. Presented from Profile and from any Plus-gated
/// feature (e.g. creating a 2nd list). Lists the benefits + the monthly/yearly
/// options with the 7-day free trial, plus the App Review-required Terms /
/// Privacy links and a Restore Purchases affordance. Dismisses itself once the
/// subscription becomes active.
struct PlusPaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    /// What Plus unlocks TODAY. Kept honest — only list what's actually gated.
    /// (Advanced Night Out + Wrapped history join this list when built as
    /// Plus-separable features.)
    private let benefits: [(icon: String, text: String)] = [
        ("rectangle.slash", "Ad-free — no banner ads"),
        ("list.star", "Unlimited lists (free: 1)"),
        ("seal.fill", "Supporter badge on your profile"),
        ("heart.fill", "Support local food coverage"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.nightOut)
                        Text("S-Tier Plus")
                            .font(.largeTitle.bold())
                        Text("Support local food coverage and unlock the extras.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(benefits, id: \.text) { b in
                            Label(b.text, systemImage: b.icon)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    if purchases.isPlus {
                        Label("You're a Plus member — thank you!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                    } else if purchases.plusProducts.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading subscription options…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(purchases.plusProducts, id: \.id) { product in
                            Button {
                                Task { await purchases.purchasePlus(product) }
                            } label: {
                                HStack {
                                    Text(planLabel(product))
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(product.displayPrice)
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(purchases.isPurchasing)
                        }
                        Text("7-day free trial, then auto-renews. Cancel anytime in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Restore Purchases") {
                        Task { await purchases.restorePurchases() }
                    }
                    .font(.subheadline)

                    HStack(spacing: 18) {
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy Policy", destination: URL(string: "https://compo-cf.github.io/woodlands-eats/privacy.html")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("S-Tier Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: purchases.isPlus) { _, nowPlus in
                if nowPlus { dismiss() }
            }
        }
    }

    /// "Monthly" / "Yearly" from the product's subscription period.
    private func planLabel(_ product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .month: return "Monthly"
        case .year: return "Yearly"
        default: return product.displayName
        }
    }
}
