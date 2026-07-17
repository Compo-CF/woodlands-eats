import SwiftUI
import StoreKit

/// v2.1: the occasional, opt-out-able tip reminder. Deliberately gentle —
/// shown at most once every 60 days (and never in the first 2 weeks, never
/// after a tip). Offers the three tips inline, a "Maybe later" (asks again
/// after the interval), and a "Don't ask again" that silences it forever.
/// Gating lives in PurchaseStore; this view is just the presentation.
struct TipReminderView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                Image(systemName: "hands.clap.fill")
                    .resizable().scaledToFit()
                    .frame(width: 78, height: 78)
                    .foregroundStyle(Tier.s.color)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 12) {
                    Text("Enjoying S-Tier Eats?")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("It's free and built by one person who lives in the area. If it's earned a spot in your routine, a small tip keeps it going — no pressure, and I won't ask often.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 10) {
                    ForEach(Array(purchases.tipProducts.enumerated()), id: \.element.id) { idx, product in
                        Button {
                            Task { await purchases.purchaseTip(product); dismiss() }
                        } label: {
                            VStack(spacing: 3) {
                                Text(["Small", "Medium", "Generous"][min(idx, 2)])
                                    .font(.caption.weight(.semibold))
                                Text(product.displayPrice)
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(purchases.isPurchasing)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 4) {
                    Button("Maybe later") { dismiss() }
                        .font(.headline)
                        .padding(.vertical, 6)
                    Button("Don't ask again") {
                        purchases.stopTipReminders()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.large])
    }
}
