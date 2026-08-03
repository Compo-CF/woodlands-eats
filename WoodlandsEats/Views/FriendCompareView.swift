import SwiftUI

/// v2.1: "Taste Match" — compares your tier list against a friend's for the
/// restaurants you've both ranked. Shows an agreement percentage and a list
/// ordered by biggest disagreement first (the fun part). Pure local + already-
/// fetched data: your TierListStore vs the friend's placements passed in from
/// FriendTierView. Tapping a row opens that restaurant.
struct FriendCompareView: View {
    let friendName: String
    let friendPlacements: [(restaurantID: UUID, tier: Tier)]

    @Environment(TierListStore.self) private var tierStore
    @Environment(RestaurantStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Restaurant?

    private struct Row: Identifiable {
        let restaurant: Restaurant
        let mine: Tier
        let theirs: Tier
        var id: UUID { restaurant.id }
        var gap: Int { abs(mine.score - theirs.score) }
        var agree: Bool { mine == theirs }
    }

    private var restaurantByID: [UUID: Restaurant] {
        Dictionary(store.restaurants.map { ($0.id, $0) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// Restaurants both of us have ranked, most-disagreement first.
    private var rows: [Row] {
        let friendMap = Dictionary(friendPlacements.map { ($0.restaurantID, $0.tier) },
                                   uniquingKeysWith: { _, latest in latest })
        var out: [Row] = []
        for (rid, mine) in tierStore.placements {
            guard let theirs = friendMap[rid], let r = restaurantByID[rid] else { continue }
            out.append(Row(restaurant: r, mine: mine, theirs: theirs))
        }
        return out.sorted {
            $0.gap != $1.gap
                ? $0.gap > $1.gap
                : $0.restaurant.name.localizedCaseInsensitiveCompare($1.restaurant.name) == .orderedAscending
        }
    }

    private var name: String {
        let t = friendName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "your friend" : t
    }
    private var agreeCount: Int { rows.filter(\.agree).count }
    private var matchPct: Int {
        rows.isEmpty ? 0 : Int((Double(agreeCount) / Double(rows.count) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No overlap yet", systemImage: "arrow.left.arrow.right")
                    } description: {
                        Text("You and \(name) haven't ranked any of the same restaurants yet. Rank a few more spots and check back.")
                    }
                } else {
                    List {
                        Section { matchHeader }
                        Section("Where you line up — and don't") {
                            ForEach(rows) { row in
                                Button { selected = row.restaurant } label: { rowView(row) }
                                    .buttonStyle(.plain)
                            }
                        }
                        // v2.2: referral loop — invite more friends to compare.
                        Section {
                            InviteFriendButton()
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Taste Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { r in
                NavigationStack { RestaurantDetailView(restaurant: r) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var matchHeader: some View {
        VStack(spacing: 6) {
            Text("\(matchPct)%")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(Tier.s.color)
            Text("taste match with \(name)")
                .font(.headline)
            Text("You've both ranked \(rows.count) spot\(rows.count == 1 ? "" : "s") · agree on \(agreeCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.restaurant.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    tierChip("You", row.mine)
                    tierChip(name, row.theirs)
                }
            }
            Spacer()
            Image(systemName: row.agree ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                .foregroundStyle(row.agree ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }

    private func tierChip(_ label: String, _ tier: Tier) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tier.label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
