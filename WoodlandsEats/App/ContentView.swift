import SwiftUI

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(VisitedStore.self) private var visitedStore
    /// Pre-v1.3 flag — kept for migration so users who already saw the
    /// old tier-guide sheet don't get the new onboarding flow either.
    /// New users go through OnboardingView in WoodlandsEatsApp instead.
    @AppStorage("WoodlandsEats.hasSeenTierGuide") private var hasSeenTierGuide = false
    @AppStorage("WoodlandsEats.hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
        .onAppear {
            // v1.3 migration: users who already completed the old tier-guide
            // first-launch flow (pre-v1.3) shouldn't be re-onboarded. Mark
            // them as completed so the new OnboardingView fullScreenCover
            // never fires for upgraders.
            if hasSeenTierGuide && !hasCompletedOnboarding {
                hasCompletedOnboarding = true
            }
        }
    }
}
