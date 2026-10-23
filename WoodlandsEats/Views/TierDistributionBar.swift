import SwiftUI

/// v3.0: a segmented "how the community voted" bar for one restaurant — the
/// in-app version of the consensus card. Shows S→F proportions with a compact
/// count legend beneath. Only renders tiers that actually got votes.
struct TierDistributionBar: View {
    let distribution: [Tier: Int]

    private var total: Int { distribution.values.reduce(0, +) }
    private var present: [Tier] { Tier.allCases.filter { (distribution[$0] ?? 0) > 0 } }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let gap: CGFloat = 3
                    let avail = geo.size.width - gap * CGFloat(max(present.count - 1, 0))
                    HStack(spacing: gap) {
                        ForEach(present, id: \.self) { tier in
                            let n = distribution[tier] ?? 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tier.color)
                                .frame(width: max(8, avail * CGFloat(n) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 16)

                HStack(spacing: 12) {
                    ForEach(present, id: \.self) { tier in
                        HStack(spacing: 3) {
                            Text(tier.label)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(tier.color)
                            Text("\(distribution[tier] ?? 0)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
