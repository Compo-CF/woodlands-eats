import SwiftUI

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()

    init() {
        // v1.1: boot AdMob early so the first banner load on the Browse
        // tab is warm. Safe to call repeatedly; the SDK no-ops if already
        // initialized.
        AdsService.shared.start()
    }

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
