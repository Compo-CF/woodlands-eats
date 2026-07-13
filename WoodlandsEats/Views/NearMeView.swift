import SwiftUI
import CoreLocation

/// v2.0 Feature 4: "Top near me right now" — the daily-habit discovery
/// hook. Answers "I'm hungry, what's great and close?" by combining the
/// two things the app uniquely has: community rankings + the user's
/// location.
///
/// Shows community-ranked restaurants sorted by distance from the user,
/// each with its consensus tier badge, cuisine, and distance. Tapping
/// opens the standard detail sheet (with call / directions / order
/// actions). Presented as a sheet from the Map tab.
///
/// Reuses the community-tier aggregation. Restaurants with no community
/// tier are omitted — this is a "top-RATED near me" view, so an unranked
/// spot has nothing to show. Falls back to a location-permission prompt
/// if we don't have the user's position yet.
struct NearMeView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.dismiss) private var dismiss

    @State private var tiers: [UUID: CommunityTier] = [:]
    @State private var loading = true
    @State private var selected: Restaurant?
    /// Only show spots at least this well-regarded, so "near me" surfaces
    /// genuinely good options rather than every rated dive nearby. Default
    /// B+ and up; a toggle relaxes it to everything ranked.
    @State private var goodOnly = true
    /// v2.1: optional cuisine filter — "best BBQ near me right now". nil = all.
    @State private var cuisineFilter: Cuisine?

    private let maxResults = 40

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Finding top spots near you…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.userLocation == nil {
                    ContentUnavailableView {
                        Label("Location needed", systemImage: "location.slash")
                    } description: {
                        Text("Turn on location access for S-Tier Eats to see the best-rated restaurants near you.")
                    }
                } else if nearby.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing ranked nearby yet", systemImage: "fork.knife")
                    } description: {
                        Text(cuisineFilter == nil
                             ? "No community-ranked spots close by. Try turning off \u{201C}Great spots only\u{201D}, or be the first to rank places around here."
                             : "No \(cuisineFilter!.displayName) spots ranked close by. Try another cuisine or turn off \u{201C}Great spots only\u{201D}.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(nearby, id: \.restaurant.id) { item in
                                Button { selected = item.restaurant } label: {
                                    row(item)
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text("Community-ranked spots, closest first. Distances are straight-line.")
                        }
                    }
                }
            }
            .navigationTitle("Near Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                // v2.1: cuisine filter — only lists cuisines actually present
                // in the nearby set, so we never offer an empty "best X" board.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            cuisineFilter = nil
                        } label: {
                            Label("All cuisines", systemImage: cuisineFilter == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(availableCuisines, id: \.self) { c in
                            Button {
                                cuisineFilter = c
                            } label: {
                                Label(c.displayName, systemImage: cuisineFilter == c ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter by cuisine")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $goodOnly) { Text("Great spots only") }
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
            .sheet(item: $selected) { r in
                NavigationStack { RestaurantDetailView(restaurant: r) }
                    .presentationDetents([.medium, .large])
            }
            .task { await load() }
        }
    }

    private struct NearbyItem {
        let restaurant: Restaurant
        let tier: CommunityTier
        let meters: CLLocationDistance
    }

    /// Ranked restaurants near the user (goodOnly + not-closed applied), sorted
    /// by distance. The cuisine filter is applied on top in `nearby`; this base
    /// also feeds `availableCuisines` so the menu only offers real options.
    private var nearbyBase: [NearbyItem] {
        guard let loc = store.userLocation else { return [] }
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        var items: [NearbyItem] = []
        for (rid, info) in tiers {
            guard let r = byID[rid] else { continue }
            if goodOnly && info.tier.score < Tier.b.score { continue }   // B and up
            // Drop admin-confirmed-closed spots from discovery (same as Map/Browse).
            if store.confirmedClosedIDs.contains(rid) { continue }
            items.append(NearbyItem(restaurant: r, tier: info, meters: r.distance(from: loc)))
        }
        return items.sorted { $0.meters < $1.meters }
    }

    /// Final list: base + cuisine filter, capped at maxResults.
    private var nearby: [NearbyItem] {
        let filtered = cuisineFilter == nil
            ? nearbyBase
            : nearbyBase.filter { $0.restaurant.cuisines.contains(cuisineFilter!) }
        return Array(filtered.prefix(maxResults))
    }

    /// Cuisines present among nearby ranked spots, most-common first.
    private var availableCuisines: [Cuisine] {
        var counts: [Cuisine: Int] = [:]
        for item in nearbyBase {
            for c in item.restaurant.cuisines { counts[c, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    @ViewBuilder
    private func row(_ item: NearbyItem) -> some View {
        HStack(spacing: 12) {
            Text(item.tier.tier.label)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(item.tier.tier.color, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.restaurant.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.restaurant.primaryCuisine.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(distanceString(item.meters))
                    .font(.subheadline.weight(.medium))
                Text("\(item.tier.count) rank\(item.tier.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func distanceString(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.344
        if miles < 0.1 { return "< 0.1 mi" }
        return String(format: "%.1f mi", miles)
    }

    private func load() async {
        // Reuse the Everyone community aggregate. Cheap-ish TRUEPREDICATE
        // walk; acceptable for an explicitly-opened discovery screen.
        let fresh = await cloudKit.fetchAllCommunityTiers()
        if !fresh.isEmpty { tiers = fresh }
        loading = false
    }
}
