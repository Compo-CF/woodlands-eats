import SwiftUI
import StoreKit

/// Modal sheet reached from the Profile tab.
///
/// Shows the app's identity (icon, name, version), a one-line tagline, an
/// optional in-app "leave a tip" jar (v2.1), contact + privacy links, and a
/// credit line. (v2.0 removed the Ko-fi link for App Review 3.1.1; v2.1
/// brings tips back the compliant way — StoreKit consumable IAPs.)
struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseStore.self) private var purchases

    private var version: String {
        let dict = Bundle.main.infoDictionary
        let v = dict?["CFBundleShortVersionString"] as? String ?? "—"
        let b = dict?["CFBundleVersion"] as? String ?? "—"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    Text(
                        "A no-stars, all-tiers restaurant discovery app "
                        + "for The Woodlands and Spring, Texas. Made by "
                        + "one person, fed by the crowd."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                    tipSection

                    linksSection

                    creditFooter
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Thank you! 🙏", isPresented: Binding(
                get: { purchases.didTip },
                set: { if !$0 { purchases.didTip = false } }
            )) {
                Button("You're welcome", role: .cancel) { purchases.didTip = false }
            } message: {
                Text("Your tip genuinely helps keep S-Tier Eats free and ad-light. It means a lot.")
            }
        }
    }

    /// v2.1: in-app tip jar (StoreKit consumables). Hidden until the
    /// products load (or if they don't exist in App Store Connect yet), so
    /// the section never shows dead buttons. Labels map small → generous;
    /// the amount comes from StoreKit's localized price, never hard-coded.
    @ViewBuilder
    private var tipSection: some View {
        let tips = purchases.tipProducts
        if !tips.isEmpty {
            VStack(spacing: 12) {
                Text("Leave a tip")
                    .font(.headline)
                Text("S-Tier Eats is free. If it's earned a spot in your routine, a tip helps keep it going.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 10) {
                    ForEach(Array(tips.enumerated()), id: \.element.id) { idx, product in
                        Button {
                            Task { await purchases.purchaseTip(product) }
                        } label: {
                            VStack(spacing: 3) {
                                Text(tipLabel(idx))
                                    .font(.caption.weight(.semibold))
                                Text(product.displayPrice)
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(purchases.isPurchasing)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func tipLabel(_ idx: Int) -> String {
        ["Small tip", "Medium tip", "Generous tip"][min(idx, 2)]
    }

    private var header: some View {
        VStack(spacing: 8) {
            // Render the app icon from the asset catalog. The 1024px source
            // is sized down by SwiftUI at runtime.
            if let ui = UIImage(named: "AppIcon-1024") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
            Text("S-Tier Eats")
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var linksSection: some View {
        VStack(spacing: 0) {
            linkRow(
                systemImage: "envelope",
                label: "Contact",
                detail: "acompofelice@outlook.com",
                url: URL(string: "mailto:acompofelice@outlook.com")!
            )
            Divider().padding(.leading, 60)
            linkRow(
                systemImage: "lock.shield",
                label: "Privacy policy",
                detail: "compo-cf.github.io",
                url: URL(string: "https://compo-cf.github.io/woodlands-eats/privacy.html")!
            )
            Divider().padding(.leading, 60)
            linkRow(
                systemImage: "exclamationmark.bubble",
                label: "Report a bug",
                detail: "github.com/Compo-CF/woodlands-eats/issues",
                url: URL(string: "https://github.com/Compo-CF/woodlands-eats/issues")!
            )
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func linkRow(systemImage: String, label: String, detail: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
    }

    private var creditFooter: some View {
        VStack(spacing: 2) {
            Text("Made by Anthony Compofelice")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("© 2026 · The Woodlands, TX")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }
}
