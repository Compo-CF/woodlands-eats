import SwiftUI

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    /// First-launch tier guide. Once the user dismisses it, this flag flips
    /// and the sheet never auto-shows again. Profile -> Tier guide still
    /// reaches it manually any time. Resets on uninstall along with EULA.
    @AppStorage("WoodlandsEats.hasSeenTierGuide") private var hasSeenTierGuide = false
    @State private var showTierGuide = false

    var body: some View {
        TabView {
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tabItem { Label("Browse", systemImage: "fork.knife") }
            MyTiersView()
                .tabItem { Label("My Tiers", systemImage: "list.number") }
            CommunityTiersView()
                .tabItem { Label("Community", systemImage: "person.3.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task {
            await cloudKit.refreshClosureCounts()
            await store.refreshLive(via: cloudKit)
            // Build 36: hydrate the local tier cache from CloudKit on
            // launch so reinstalls / device restores don't appear to lose
            // ranking data. Only fires when local cache is empty — see
            // TierListStore.restoreFromCloud for the guard rationale.
            await tierStore.restoreFromCloud(via: cloudKit)
        }
        .onAppear {
            // Defer one runloop tick so the tab bar finishes its initial
            // layout before the sheet animation kicks in — otherwise the
            // sheet's first frame can clip the tab bar transition.
            if !hasSeenTierGuide {
                DispatchQueue.main.async { showTierGuide = true }
            }
        }
        .sheet(isPresented: $showTierGuide, onDismiss: {
            hasSeenTierGuide = true
        }) {
            TierGuideView()
        }
    }
}
