import SwiftUI

/// Small colored letter chip showing a tier (S/A/B/C/F).
struct TierBadge: View {
    let tier: Tier
    var size: CGFloat = 28

    var body: some View {
        Text(tier.label)
            .font(.system(size: size * 0.6, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tier.color, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

/// Horizontal S A B C F selector. Tapping a tier sets it; tapping the
/// currently-selected tier again clears the placement.
struct TierPicker: View {
    let current: Tier?
    let onSelect: (Tier) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Tier.allCases) { tier in
                Button {
                    if current == tier { onClear() } else { onSelect(tier) }
                } label: {
                    Text(tier.label)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(current == tier ? .white : tier.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(current == tier ? tier.color : tier.color.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(tier.color, lineWidth: current == tier ? 0 : 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
