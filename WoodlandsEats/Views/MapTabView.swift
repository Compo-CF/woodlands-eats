import SwiftUI
import MapKit
import UIKit

/// User-selectable map presentation. Persisted by MapTabView via
/// @AppStorage so the choice survives launches. `mkMapType` projects to
/// the UIKit enum that ClusteringMapView passes to MKMapView.
enum MapStyle: Int, CaseIterable, Identifiable {
    case standard = 0
    case hybrid = 1     // satellite imagery + road/place labels (best of both)
    case satellite = 2  // satellite only, no labels

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Hybrid"
        case .satellite: "Satellite"
        }
    }

    var mkMapType: MKMapType {
        switch self {
        case .standard: .standard
        case .hybrid: .hybrid
        case .satellite: .satellite
        }
    }
}

struct MapTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(LocationManager.self) private var locationManager
    @State private var selected: Restaurant?

    /// Build 38: persisted map style across launches.
    @AppStorage("WoodlandsEats.mapStyle") private var rawMapStyle: Int = MapStyle.standard.rawValue
    private var mapStyle: MapStyle {
        MapStyle(rawValue: rawMapStyle) ?? .standard
    }

    /// Build 38: cluster-list fallback. When the user taps a cluster
    /// that's already at max zoom (pins won't separate by zooming more),
    /// ClusteringMapView calls back here with the restaurants inside the
    /// cluster, we show ClusterListSheet so the user can still pick one.
    @State private var clusterRestaurants: [Restaurant] = []
    @State private var showClusterSheet = false
    /// Pending restaurant to open in detail AFTER the cluster sheet has
    /// finished dismissing. SwiftUI can't show two sheets simultaneously,
    /// so we stash and present on the cluster sheet's onDismiss.
    @State private var pendingDetailRestaurant: Restaurant?

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
                mapType: mapStyle.mkMapType,
                selected: $selected,
                onClusterAtMaxZoom: { restaurants in
                    clusterRestaurants = restaurants
                    showClusterSheet = true
                }
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
            .sheet(isPresented: $showClusterSheet, onDismiss: {
                // After the cluster sheet has fully dismissed, open the
                // restaurant detail for whatever the user tapped (if any).
                if let pending = pendingDetailRestaurant {
                    pendingDetailRestaurant = nil
                    selected = pending
                }
            }) {
                ClusterListSheet(
                    restaurants: clusterRestaurants,
                    tierColor: { id in tierStore.tier(for: id)?.color ?? .gray },
                    onSelect: { tapped in
                        // Stash the choice; the .sheet's onDismiss above
                        // will route it to the detail-sheet binding.
                        pendingDetailRestaurant = tapped
                        showClusterSheet = false
                    }
                )
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestPermission()
                }
            }
            .navigationTitle("S-Tier Eats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Build 38: map-style picker. Menu shows the current
                    // selection with a checkmark; tap any other option to
                    // switch. Persists across launches via @AppStorage.
                    Menu {
                        ForEach(MapStyle.allCases) { style in
                            Button {
                                rawMapStyle = style.rawValue
                            } label: {
                                if mapStyle == style {
                                    Label(style.displayName, systemImage: "checkmark")
                                } else {
                                    Text(style.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "map")
                    }
                }
            }
        }
    }
}
