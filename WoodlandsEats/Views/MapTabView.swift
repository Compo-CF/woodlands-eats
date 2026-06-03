import SwiftUI
import MapKit

struct MapTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(LocationManager.self) private var locationManager
    @State private var selected: Restaurant?
    // .automatic frames whatever restaurants are currently loaded, so the map
    // adapts to the seed's coverage without a hardcoded region.
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Map(position: $position, selection: $selected) {
                ForEach(store.filteredRestaurants) { r in
                    Marker(r.name, systemImage: "fork.knife", coordinate: r.coordinate)
                        .tint(tierStore.tier(for: r.id)?.color ?? .gray)
                        .tag(r)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
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
