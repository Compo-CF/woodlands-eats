import SwiftUI

/// The crowd's consensus tier list: every restaurant the community has ranked,
/// placed into S/A/B/C/F by its average score. Tap a spot for its detail
/// (including that restaurant's own community tier + count).
struct CommunityTiersView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CloudKitService.self) private var cloudKit
    @State private var tiers: [UUID: CommunityTier] = [:]
    @State private var loading = true
    @State private var selected: Restaurant?
    @State private var mode: CommunityMode = .everyone

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading community rankings…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tiers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Tier.allCases) { tier in
                                CommunityTierRow(
                                    tier: tier,
                                    entries: entries(for: tier),
                                    onTap: { selected = $0 }
                                )
                            }
                            Text("\(rankedCount) restaurants ranked by \(mode == .pros ? "Foodie Pros" : "the community")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Community")
            .safeAreaInset(edge: .top) {
                Picker("Mode", selection: $mode) {
                    Text("Everyone").tag(CommunityMode.everyone)
                    Text("Foodie Pros").tag(CommunityMode.pros)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .onChange(of: mode) { _, _ in
                Task { await load() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task {
                if tiers.isEmpty { await load() }
            }
            .sheet(item: $selected) { restaurant in
                NavigationStack {
                    RestaurantDetailView(restaurant: restaurant)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var rankedCount: Int { tiers.count }

    private func load() async {
        loading = true
        tiers = mode == .pros
            ? await cloudKit.fetchProCommunityTiers()
            : await cloudKit.fetchAllCommunityTiers()
        loading = false
    }

    /// Restaurants whose consensus tier matches `tier`, most-ranked first.
    private func entries(for tier: Tier) -> [CommunityEntry] {
        // `uniquingKeysWith` defensive form (see ClusteringMapView for why):
        // the seed can contain duplicate UUIDs from imperfect dedup, and
        // `uniqueKeysWithValues` traps on those.
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        return tiers.compactMap { rid, info -> CommunityEntry? in
            guard info.tier == tier, let restaurant = byID[rid] else { return nil }
            return CommunityEntry(restaurant: restaurant, info: info)
        }
        .sorted {
            $0.info.count != $1.info.count
                ? $0.info.count > $1.info.count
                : $0.info.average > $1.info.average
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(mode == .pros ? "No Foodie Pro rankings yet" : "No community rankings yet",
                  systemImage: mode == .pros ? "star" : "person.3")
        } description: {
            Text(mode == .pros
                 ? "Once Foodie Pros rank places, their expert consensus tier list appears here."
                 : "Once you and others rank places, the crowd's consensus tier list appears here. Open a restaurant and drop it into a tier to get it started.")
        }
    }
}

enum CommunityMode {
    case everyone, pros
}

private struct CommunityEntry: Identifiable {
    let restaurant: Restaurant
    let info: CommunityTier
    var id: UUID { restaurant.id }
}

private struct CommunityTierRow: View {
    let tier: Tier
    let entries: [CommunityEntry]
    let onTap: (Restaurant) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tier.label)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 64)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 14))

            if entries.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entries) { entry in
                            Button {
                                onTap(entry.restaurant)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(entry.restaurant.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text("\(entry.info.count) ranked")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 104, height: 56)
                                .padding(6)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
