import SwiftUI
import CoreLocation

struct RestaurantRow: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(VisitedStore.self) private var visitedStore
    let restaurant: Restaurant

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(restaurant.name)
                        .font(.headline)
                        .strikethrough(isClosed, color: .red)
                    if visitedStore.isVisited(restaurant.id) {
                        // v1.2: subtle "you've been here" marker. Small,
                        // muted green check so it doesn't compete with
                        // the tier badge for attention.
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .accessibilityLabel("Visited")
                    }
                }
                if isClosed {
                    Text("Reported closed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Text(restaurant.cuisineSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(restaurant.priceTier.displayName)
                    Text("·")
                    Text(restaurant.area.displayName)
                    if let d = distanceText {
                        Text("·")
                        Text(d)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let tier = tierStore.tier(for: restaurant.id) {
                TierBadge(tier: tier)
            }
        }
        .padding(.vertical, 4)
    }

    private var isClosed: Bool {
        (cloudKit.closureCounts[restaurant.id] ?? 0) > 0
    }

    private var distanceText: String? {
        guard let loc = store.userLocation else { return nil }
        let miles = restaurant.distance(from: loc) / 1609.34
        return String(format: "%.1f mi", miles)
    }
}
