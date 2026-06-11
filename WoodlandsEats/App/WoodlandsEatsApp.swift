import SwiftUI

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()
    /// App Review Guideline 1.2 (UGC) requires an EULA gate that the user must
    /// accept before using the app. Persisted in @AppStorage so it survives
    /// launches but resets on uninstall — the latter is intentional so a fresh
    /// install presents the EULA again. Until the flag flips, the EULAView
    /// fully replaces ContentView.
    @AppStorage("WoodlandsEats.hasAcceptedEULA") private var hasAcceptedEULA = false

    var body: some Scene {
        WindowGroup {
            if hasAcceptedEULA {
                ContentView()
                    .environment(store)
                    .environment(tierStore)
                    .environment(locationManager)
                    .environment(cloudKit)
                    .environment(blockList)
                    .onChange(of: locationManager.location) { _, newValue in
                        store.userLocation = newValue
                    }
            } else {
                EULAView(hasAccepted: $hasAcceptedEULA)
            }
        }
    }
}
