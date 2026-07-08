import SwiftUI

/// Modal sheet reached from the Profile tab.
///
/// Shows the app's identity (icon, name, version), a one-line tagline,
/// contact + privacy links, and a credit line. Mirrors the pattern
/// shipped in Woodlands Fishing v1.3. (v2.0: the Ko-fi support button was
/// removed for App Review Guideline 3.1.1 — tips for a digital service must
/// use IAP, not an external link.)
struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss

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
        }
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
