import SwiftUI

/// v1.2: Browse list sort modes. Persisted via @AppStorage so the user's
/// pick survives launches. Tier sort orders restaurants by the user's
/// personal tier (S/A/B/C/F, then unranked at the bottom), tie-broken by
/// name within each tier.
enum BrowseSortMode: String, CaseIterable, Identifiable {
    case nearby = "Nearby"
    case alphabetical = "A–Z"
    case tier = "Tier"

    var id: String { rawValue }
}

struct ListTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    /// v1.5: programmatic tab switching for the rank-icon shortcut.
    @Environment(TabRouter.self) private var tabRouter

    /// v1.2: persisted three-way sort. Default Nearby for first launch.
    @AppStorage("WoodlandsEats.browseSortMode") private var rawSortMode: String = BrowseSortMode.nearby.rawValue
    private var sortMode: BrowseSortMode {
        BrowseSortMode(rawValue: rawSortMode) ?? .nearby
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                ForEach(sorted) { r in
                    NavigationLink(value: r) {
                        RestaurantRow(restaurant: r)
                    }
                }
            }
            .listStyle(.plain)
            // Build 28: drag-to-dismiss-keyboard on the list. Works with the
            // FilterBar's Done toolbar button as a second exit path; either
            // one releases focus so the keyboard collapses and the tab bar
            // reappears.
            .scrollDismissesKeyboard(.immediately)
            .navigationDestination(for: Restaurant.self) { r in
                RestaurantDetailView(restaurant: r)
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    FilterBar(filter: $store.filter)
                    Picker("Sort", selection: Binding(
                        get: { sortMode },
                        set: { rawSortMode = $0.rawValue }
                    )) {
                        ForEach(BrowseSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .background(.thinMaterial)
            }
            .overlay {
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "fork.knife",
                        description: Text("Try clearing filters or your search.")
                    )
                }
            }
            // v1.1: AdMob banner pinned to the bottom of the Browse tab.
            // safeAreaInset reserves space so list rows aren't covered.
            // 50pt height = standard 320x50 banner; the SDK auto-centers.
            .safeAreaInset(edge: .bottom) {
                BannerAdView()
                    .frame(height: 50)
                    .background(.thinMaterial)
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // v1.5: rank-icon shortcut to Profile. Hidden for
                // zero-placement users (no rank yet).
                if let rank = FoodieRank.from(placementCount: tierStore.placements.count) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            tabRouter.selectedTab = .profile
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(rank.tintColor)
                                    .frame(width: 30, height: 30)
                                Image(systemName: rank.symbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(rank.color)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .accessibilityLabel("Your rank: \(rank.displayName). Tap to open Profile.")
                    }
                }
            }
        }
    }

    private var sorted: [Restaurant] {
        let base: [Restaurant]
        switch sortMode {
        case .nearby:
            base = store.restaurantsSortedByDistance
        case .alphabetical:
            base = store.restaurantsSortedByName
        case .tier:
            // S=5, A=4, B=3, C=2, F=1, unranked=0. Higher tier first,
            // then alphabetical within each tier. Unranked restaurants
            // settle at the bottom in name order — useful so you can
            // still scroll to find spots you haven't placed yet.
            base = store.filteredRestaurants.sorted { a, b in
                let aScore = tierStore.tier(for: a.id)?.score ?? 0
                let bScore = tierStore.tier(for: b.id)?.score ?? 0
                if aScore != bScore { return aScore > bScore }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
        guard store.filter.rankedOnly else { return base }
        return base.filter { tierStore.tier(for: $0.id) != nil }
    }
}
