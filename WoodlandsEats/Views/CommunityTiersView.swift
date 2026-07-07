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
    /// v2.0 Feature 1: nil = all cuisines (global board); non-nil filters
    /// the consensus board to one cuisine ("best BBQ", "best sushi", …).
    /// Client-side filter over the already-aggregated tiers — no extra
    /// CloudKit work, so switching cuisines is instant.
    @State private var cuisineFilter: Cuisine?

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
                            Text("\(rankedCount) restaurants · \(scopeLabel)")
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
                // v2.0 Feature 1: cuisine picker. Only lists cuisines that
                // actually appear in the current community board, so we
                // don't offer empty "best Ethiopian" boards.
                ToolbarItem(placement: .topBarLeading) {
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
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(cuisineFilter?.displayName ?? "All")
                                .font(.subheadline)
                        }
                    }
                }
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

    /// Count reflecting the active cuisine filter (all tiers combined).
    private var rankedCount: Int {
        guard let c = cuisineFilter else { return tiers.count }
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        return tiers.keys.filter { byID[$0]?.cuisines.contains(c) ?? false }.count
    }

    /// Cuisines present in the current community board, sorted by how many
    /// ranked restaurants each has (most-populated first) so the useful
    /// boards surface at the top of the menu.
    private var availableCuisines: [Cuisine] {
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        var counts: [Cuisine: Int] = [:]
        for rid in tiers.keys {
            for c in byID[rid]?.cuisines ?? [] { counts[c, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Label for the current board scope, used in the caption + share.
    private var scopeLabel: String {
        let who = mode == .pros ? "Foodie Pros" : "the community"
        if let c = cuisineFilter { return "\(c.displayName) · ranked by \(who)" }
        return "ranked by \(who)"
    }

    /// v1.3.1: stale-while-revalidate cache. Hits a UserDefaults-backed
    /// cache first to render instantly, then fetches fresh in the
    /// background. Without this, every Community-tab open paged through
    /// all Placement records in CloudKit (TRUEPREDICATE) and aggregated
    /// client-side — 2-5s at current scale, 8-15s once the community
    /// grows. Now: cache hit = instant; background fetch updates the UI
    /// when it lands. Pull-to-refresh + the toolbar refresh button still
    /// force a fresh fetch via this same path. Empty fetch results
    /// don't overwrite a populated cache (transient CloudKit errors
    /// don't blank the screen).
    private func load() async {
        if let cached = Self.loadCache(for: mode) {
            tiers = cached
            loading = false   // instant render
        } else {
            loading = true
        }
        let fresh = mode == .pros
            ? await cloudKit.fetchProCommunityTiers()
            : await cloudKit.fetchAllCommunityTiers()
        if !fresh.isEmpty {
            tiers = fresh
            Self.saveCache(fresh, for: mode)
        }
        loading = false
    }

    // MARK: - Cache

    private static let cacheTTLSeconds: TimeInterval = 300  // 5 min — stale but acceptable; the background fetch always runs

    private static func cacheKey(for mode: CommunityMode) -> String {
        "WoodlandsEats.communityCache.\(mode == .pros ? "pros" : "everyone")"
    }

    private static func loadCache(for mode: CommunityMode) -> [UUID: CommunityTier]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: mode)),
              let cached = try? JSONDecoder().decode(CachedCommunityTiers.self, from: data) else {
            return nil
        }
        // Honor the TTL by ignoring really-stale caches — the user would
        // still see a spinner once instead of stale data on top of a
        // background fetch that might take 5+ seconds.
        if Date().timeIntervalSince(cached.timestamp) > cacheTTLSeconds * 12 {  // 1h hard expiry
            return nil
        }
        return Dictionary(uniqueKeysWithValues: cached.entries.compactMap { entry in
            guard let id = UUID(uuidString: entry.restaurantID),
                  let tier = Tier(rawValue: entry.tierRaw) else { return nil }
            return (id, CommunityTier(tier: tier, count: entry.count, average: entry.average))
        })
    }

    private static func saveCache(_ tiers: [UUID: CommunityTier], for mode: CommunityMode) {
        let entries = tiers.map { id, info in
            CachedCommunityTiers.Entry(
                restaurantID: id.uuidString,
                tierRaw: info.tier.rawValue,
                count: info.count,
                average: info.average
            )
        }
        let payload = CachedCommunityTiers(timestamp: Date(), entries: entries)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey(for: mode))
        }
    }

    /// v1.5: launch-time prefetch. Warms the Everyone + Pros caches so
    /// the user's first tap on the Community tab renders fresh data
    /// instantly instead of showing cached-then-updating. Called fire-
    /// and-forget from ContentView.task — doesn't block other launch
    /// work; if it fails (network/CloudKit down) the existing in-tab
    /// stale-while-revalidate flow still works.
    static func prefetchCache(via cloudKit: CloudKitService) async {
        let everyone = await cloudKit.fetchAllCommunityTiers()
        if !everyone.isEmpty {
            saveCache(everyone, for: .everyone)
        }
        let pros = await cloudKit.fetchProCommunityTiers()
        if !pros.isEmpty {
            saveCache(pros, for: .pros)
        }
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
            // v2.0 Feature 1: cuisine filter. A restaurant matches if the
            // selected cuisine is anywhere in its cuisines list (not just
            // primary) so e.g. a Tex-Mex place also shows under Mexican
            // if tagged both.
            if let c = cuisineFilter, !restaurant.cuisines.contains(c) { return nil }
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

/// Codable shape of the community-tier cache. CommunityTier itself isn't
/// Codable (Tier color/blurb pull from SwiftUI, awkward to serialize),
/// so the cache flattens it to plain types and reconstructs on load.
private struct CachedCommunityTiers: Codable {
    let timestamp: Date
    let entries: [Entry]
    struct Entry: Codable {
        let restaurantID: String
        let tierRaw: String
        let count: Int
        let average: Double
    }
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
