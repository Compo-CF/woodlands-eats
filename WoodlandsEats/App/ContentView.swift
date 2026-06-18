import SwiftUI

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(VisitedStore.self) private var visitedStore

    /// v1.4: gates the rank-up celebration. Stores the displayName of
    /// the most-recently-celebrated FoodieRank so we don't show the
    /// sheet twice for the same tier. Empty on a fresh install — set
    /// in .task as a one-time silent migration (so v1.3 → v1.4
    /// upgraders with 30+ placements don't get spammed for tiers they
    /// already earned).
    @AppStorage("WoodlandsEats.lastCelebratedRank") private var lastCelebratedRank = ""
    @State private var celebratingRank: FoodieRank?
    /// Guards .onChange against firing celebrations during the launch-
    /// time CloudKit restore (which retroactively sets placements from
    /// 0 to the user's actual count). Flipped to true at the end of
    /// .task once we've absorbed any restored data and migrated the
    /// lastCelebratedRank baseline.
    @State private var hasFinishedLaunchSync = false

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
            // v1.4: silent rank-migration baseline. After the CloudKit
            // restore has settled, stamp lastCelebratedRank to match
            // wherever the user actually is so future .onChange events
            // only fire celebrations for genuinely-new tier-ups.
            //  • Fresh install with 0 placements → stamps "Newcomer"
            //    (sentinel; the first real celebration is Foodie at 5).
            //  • v1.3 user with 30 placements → stamps "Connoisseur"
            //    silently; next celebration is Tastemaker at 60.
            //  • Returning v1.4 user — lastCelebratedRank is whatever
            //    they earned last session; only bump if restore brought
            //    them up further (unlikely but possible cross-device).
            let restoredRank = FoodieRank.from(placementCount: tierStore.placements.count)
            if lastCelebratedRank.isEmpty {
                lastCelebratedRank = restoredRank?.displayName ?? FoodieRank.newcomer.displayName
            } else if let restoredRank,
                      let lastIdx = FoodieRank.allCases.firstIndex(where: { $0.displayName == lastCelebratedRank }),
                      restoredRank.rawValue > lastIdx {
                // CloudKit restore lifted the user past the last
                // recorded tier — sync silently rather than fire a
                // celebration for a tier earned on another device.
                lastCelebratedRank = restoredRank.displayName
            }
            hasFinishedLaunchSync = true
        }
        .onChange(of: tierStore.placements.count) { _, newCount in
            // Suppress all celebrations until launch sync settles —
            // otherwise restoreFromCloud's retroactive jump from 0 to
            // N would trigger a spurious celebration for the user's
            // existing rank on every app launch.
            guard hasFinishedLaunchSync else { return }
            // Newcomer is skipped — too quiet a milestone to interrupt
            // the flow on a first placement.
            guard let current = FoodieRank.from(placementCount: newCount),
                  current != .newcomer,
                  current.displayName != lastCelebratedRank else { return }
            celebratingRank = current
            lastCelebratedRank = current.displayName
        }
        .sheet(item: $celebratingRank) { rank in
            RankCelebrationView(rank: rank, placementCount: tierStore.placements.count)
        }
    }
}
