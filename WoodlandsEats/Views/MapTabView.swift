import SwiftUI
import MapKit
import UIKit

struct MapTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(LocationManager.self) private var locationManager
    @State private var selected: Restaurant?

    /// Build 28: applies the "Ranked only" filter on top of the textual /
    /// area / cuisine filters. Done at the view layer (rather than inside
    /// RestaurantStore) because only the views see TierListStore.
    private var visibleRestaurants: [Restaurant] {
        let base = store.filteredRestaurants
        guard store.filter.rankedOnly else { return base }
        return base.filter { tierStore.tier(for: $0.id) != nil }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            // v1.1: native MKMapView with clustering. At 1,854 pins the
            // declarative SwiftUI Map turned the screen into a wall of dots;
            // MKMapView's clusteringIdentifier groups nearby pins into a
            // single badge per zoom level.
            ClusteringMapView(
                restaurants: visibleRestaurants,
                tierColor: { id in
                    UIColor(tierStore.tier(for: id)?.color ?? .gray)
                },
                selected: $selected
            )
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                FilterBar(filter: $store.filter)
                    .background(.thinMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                // v1.1: banner ad mirrors the Browse tab. With
                // `.ignoresSafeArea(.bottom)` on the map above, the map paints
                // behind the translucent banner so it doesn't feel boxed-in.
                BannerAdView()
                    .frame(height: 50)
                    .background(.thinMaterial)
            }
            .sheet(item: $selected) { r in
                NavigationStack {
                    RestaurantDetailView(restaurant: r)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestPermission()
                }
            }
            .navigationTitle("S-Tier Eats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
