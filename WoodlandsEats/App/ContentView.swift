import SwiftUI

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(VisitedStore.self) private var visitedStore

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
            // v1.3: same idea for the personal visited list. Recovers
            // visited badges after reinstall and pulls in updates from
            // other devices (toggled on iPhone, restored next iPad launch).
            await visitedStore.restoreFromCloud(via: cloudKit)
        }
    }
}
