import SwiftUI
import MapKit
import UIKit

struct MapTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(LocationManager.self) private var locationManager
    @State private var selected: Restaurant?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            // v1.1: native MKMapView with clustering. At 1,854 pins the
            // declarative SwiftUI Map turned the screen into a wall of dots;
            // MKMapView's clusteringIdentifier groups nearby pins into a
            // single badge per zoom level.
            ClusteringMapView(
                restaurants: store.filteredRestaurants,
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
