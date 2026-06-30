import SwiftUI

/// v1.4: tier-up celebration. Presented from ContentView as a sheet
/// when the user's FoodieRank changes upward (detected via .onChange
/// on tierStore.placements.count). One celebration per tier crossed,
/// never repeated — gated by @AppStorage("WoodlandsEats.lastCelebratedRank")
/// in ContentView. Newcomer is skipped (boring rank, no dopamine).
///
/// Designed to be brief: full-screen impression, one action ("Got it"),
/// dismiss. No buttons that take the user elsewhere — the goal is to
/// reward, not to interrupt their flow into a different screen.
struct RankCelebrationView: View {
    let rank: FoodieRank
    let placementCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("You leveled up.")
                .font(.title3)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(rank.tintColor)
                    .frame(width: 160, height: 160)
                Image(systemName: rank.symbolName)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(rank.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(rank.displayName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(rank.color)
                Text(rank.blurb)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("\(placementCount) restaurants ranked")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            if let next = rank.next {
                let togo = next.minPlacements - placementCount
                Text("\(togo) more to reach \(next.displayName).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            } else {
                Text("You've reached the top tier.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(rank.color)
                    .padding(.top, 4)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(rank.color, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
