import SwiftUI

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(tierStore)
                .environment(locationManager)
                .environment(cloudKit)
                .environment(blockList)
                .onChange(of: locationManager.location) { _, newValue in
                    store.userLocation = newValue
                }
        }
    }
}
