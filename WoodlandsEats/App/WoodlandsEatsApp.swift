import SwiftUI

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(tierStore)
                .environment(locationManager)
                .onChange(of: locationManager.location) { _, newValue in
                    store.userLocation = newValue
                }
        }
    }
}
