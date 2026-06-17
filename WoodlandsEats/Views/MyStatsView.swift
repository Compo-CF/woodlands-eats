import SwiftUI

/// v1.3: personal activity dashboard. Aggregates the user's tier
/// placements + visited list + restaurant catalog into a read-only
/// stats view. Pure computation, no CloudKit fetches — all data is
/// already loaded on launch via the in-memory stores.
///
/// Reached from ProfileView via a "My activity" NavigationLink.
struct MyStatsView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(VisitedStore.self) private var visitedStore

    private var visitedCount: Int { visitedStore.visited.count }
    private var totalCount: Int { store.restaurants.count }
    private var rankedCount: Int { tierStore.placements.count }

    private var visitedPercent: Double {
        guard totalCount > 0 else { return 0 }
        return Double(visitedCount) / Double(totalCount)
    }

    /// Count of placements per tier (S/A/B/C/F).
    private var tierDistribution: [Tier: Int] {
        Dictionary(grouping: tierStore.placements.values, by: { $0 })
            .mapValues { $0.count }
    }

    /// Top 5 cuisines by ranked count. Multi-cuisine restaurants
    /// contribute to multiple buckets (a "Tex-Mex + American" spot
    /// increments both counts).
    private var topCuisines: [(cuisine: Cuisine, count: Int)] {
        var counts: [Cuisine: Int] = [:]
        for r in store.restaurants where tierStore.isRanked(r.id) {
            for c in r.cuisines where c != .other {
                counts[c, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }

    /// Per-area: ranked + visited counts. Sorted by ranked desc.
    /// Areas with zero activity drop out so the list stays compact.
    private var areaActivity: [(area: Area, ranked: Int, visited: Int)] {
        var ranked: [Area: Int] = [:]
        var visited: [Area: Int] = [:]
        for r in store.restaurants {
            if tierStore.isRanked(r.id) { ranked[r.area, default: 0] += 1 }
            if visitedStore.isVisited(r.id) { visited[r.area, default: 0] += 1 }
        }
        return Area.allCases
            .map { ($0, ranked[$0] ?? 0, visited[$0] ?? 0) }
            .filter { $0.1 > 0 || $0.2 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.2 > rhs.2
            }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                visitedCard
                tiersCard
                if !topCuisines.isEmpty { cuisinesCard }
                if !areaActivity.isEmpty { areaCard }
                if rankedCount == 0 && visitedCount == 0 { emptyState }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cards

    private var visitedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Restaurants visited", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(visitedCount)")
                    .font(.system(size: 44, weight: .bold))
                Text("of \(totalCount)")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: visitedPercent)
                .tint(.green)
            Text(String(format: "%.1f%% of the catalog", visitedPercent * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var tiersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tiers placed", systemImage: "list.number")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(rankedCount)")
                    .font(.system(size: 44, weight: .bold))
                Text("restaurants ranked")
                    .foregroundStyle(.secondary)
            }
            if rankedCount > 0 {
                tierBar
                tierLegend
            } else {
                Text("Tap any restaurant to place it in a tier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    /// Horizontal stacked bar showing tier proportions S→F left to right.
    private var tierBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Tier.allCases) { tier in
                    let count = tierDistribution[tier] ?? 0
                    let width = rankedCount > 0
                        ? geo.size.width * CGFloat(count) / CGFloat(rankedCount)
                        : 0
                    Rectangle()
                        .fill(tier.color)
                        .frame(width: max(0, width - 2))
                }
            }
        }
        .frame(height: 18)
        .clipShape(Capsule())
    }

    private var tierLegend: some View {
        HStack(spacing: 10) {
            ForEach(Tier.allCases) { tier in
                let count = tierDistribution[tier] ?? 0
                HStack(spacing: 4) {
                    Circle().fill(tier.color).frame(width: 8, height: 8)
                    Text("\(tier.label): \(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count > 0 ? .primary : .tertiary)
                }
            }
        }
    }

    private var cuisinesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Top cuisines you've ranked", systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(topCuisines, id: \.cuisine) { item in
                    HStack(spacing: 6) {
                        Text(item.cuisine.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text("\(item.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground),
                                in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var areaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Areas explored", systemImage: "map.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            ForEach(areaActivity, id: \.area) { item in
                HStack {
                    Text(item.area.displayName)
                        .font(.callout.weight(.medium))
                    Spacer()
                    if item.visited > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("\(item.visited)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if item.ranked > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "list.number")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(item.ranked)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Start ranking and marking visits to see your stats here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }
}
