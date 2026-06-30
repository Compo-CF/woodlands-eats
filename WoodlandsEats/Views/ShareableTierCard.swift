import SwiftUI

/// v1.6: A square-friendly tier-list card rendered to a UIImage via
/// ImageRenderer so users can share their S/A/B/C/F board to Instagram,
/// Messages, Twitter, etc. Lives off-screen — never shown directly in
/// the app's view tree.
///
/// Fixed 1080×1350 (4:5 portrait) so it looks correct on Instagram
/// posts, Stories, Twitter, and in iMessage previews. ImageRenderer
/// applies the displayScale multiplier so the final PNG is sharp.
struct ShareableTierCard: View {
    let displayName: String
    let placementsByTier: [Tier: [Restaurant]]
    /// Per-tier cap — beyond this we show "+N more" so the card doesn't
    /// overflow vertically when a power-user has 50+ rankings in one tier.
    private let perTierCap = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 40)
            tierRows
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 1080, height: 1350)
        .background(Color(.systemBackground))
        // Force light mode for the rendered image. The shared image is
        // for OTHER people to see (Instagram, iMessage); we want it to
        // look the same regardless of the source user's color scheme.
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("S-TIER EATS")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(.secondary)
            Text(byline)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 40)
            Text("The Woodlands · Spring · Conroe")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 56)
        .padding(.bottom, 24)
    }

    private var byline: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "My Tier List" : "\(trimmed)'s Tier List"
    }

    private var tierRows: some View {
        VStack(spacing: 18) {
            ForEach(Tier.allCases) { tier in
                tierRow(for: tier)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
    }

    private func tierRow(for tier: Tier) -> some View {
        let restaurants = placementsByTier[tier] ?? []
        let shown = Array(restaurants.prefix(perTierCap))
        let extra = restaurants.count - shown.count

        return HStack(alignment: .top, spacing: 16) {
            Text(tier.label)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 20))

            if restaurants.isEmpty {
                Text("—")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                ChipFlow {
                    ForEach(shown) { r in
                        chip(text: r.name)
                    }
                    if extra > 0 {
                        chip(text: "+\(extra) more", isMore: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            }
        }
    }

    private func chip(text: String, isMore: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 20, weight: isMore ? .bold : .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundStyle(isMore ? .secondary : .primary)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Rank your local restaurants")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("apps.apple.com/app/id6773501518")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 40)
    }
}

/// Minimal wrap-to-fit layout for the restaurant chips. iOS 16's Layout
/// protocol; lays children left-to-right and wraps to a new line when
/// width is exceeded. We don't need anything fancier than this.
private struct ChipFlow: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = laidOut(subviews: subviews, maxWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * vSpacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = laidOut(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            var x = bounds.minX
            for (sub, size) in row.items {
                _ = sub
                subviews[subviewIndex].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + hSpacing
                subviewIndex += 1
            }
            y += row.height + vSpacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func laidOut(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let needsNewRow = !rows[rows.endIndex - 1].items.isEmpty &&
                rows[rows.endIndex - 1].width + hSpacing + size.width > maxWidth
            if needsNewRow {
                rows.append(Row())
            }
            var row = rows[rows.endIndex - 1]
            let addSpacing = row.items.isEmpty ? 0 : hSpacing
            row.items.append((i, size))
            row.width += size.width + addSpacing
            row.height = max(row.height, size.height)
            rows[rows.endIndex - 1] = row
        }
        return rows
    }
}
