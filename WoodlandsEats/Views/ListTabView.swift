import SwiftUI

struct ListTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @State private var sortByDistance = true

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
                    Picker("Sort", selection: $sortByDistance) {
                        Text("Nearby").tag(true)
                        Text("A–Z").tag(false)
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
        }
    }

    private var sorted: [Restaurant] {
        let base = sortByDistance ? store.restaurantsSortedByDistance : store.restaurantsSortedByName
        guard store.filter.rankedOnly else { return base }
        return base.filter { tierStore.tier(for: $0.id) != nil }
    }
}
