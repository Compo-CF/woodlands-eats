import SwiftUI
// StoreKit provides the EnvironmentValues.requestReview extension —
// without this import, `\.requestReview` can't be resolved as an
// EnvironmentValues key path and the compiler emits 'Cannot infer
// key path type from context'.
import StoreKit

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(VisitedStore.self) private var visitedStore
    @Environment(TabRouter.self) private var tabRouter

    /// v1.4: gates the rank-up celebration. Stores the displayName of
    /// the most-recently-celebrated FoodieRank so we don't show the
    /// sheet twice for the same tier. Empty on a fresh install — set
    /// in .task as a one-time silent migration (so v1.3 → v1.4
    /// upgraders with 30+ placements don't get spammed for tiers they
    /// already earned).
    @AppStorage("WoodlandsEats.lastCelebratedRank") private var lastCelebratedRank = ""
    /// v1.5: one-shot flags for the milestone prompts. Keys suffix-
    /// versioned so a future major release can re-ask (bump to .v1.6
    /// in a later major and users get one more chance to engage).
    @AppStorage("WoodlandsEats.hasSeenReviewPrompt.v1.5") private var hasSeenReviewPrompt = false
    @AppStorage("WoodlandsEats.hasSeenKofiPrompt.v1.5") private var hasSeenKofiPrompt = false
    /// v1.5: Apple's native review-request action. Internally capped
    /// by Apple to 3 prompts/year regardless of how often we call it,
    /// so the hasSeenReviewPrompt flag is just to control WHEN we ask.
    @Environment(\.requestReview) private var requestReview
    @State private var celebratingRank: FoodieRank?
    /// v1.5: remembers which tier just got celebrated so the onDismiss
    /// of the celebration sheet can fire the right secondary prompt
    /// (review at Critic, Ko-fi at Connoisseur). Cleared after handling.
    @State private var pendingPostCelebrationRank: FoodieRank?
    @State private var showKofiSheet = false
    /// Guards .onChange against firing celebrations during the launch-
    /// time CloudKit restore (which retroactively sets placements from
    /// 0 to the user's actual count). Flipped to true at the end of
    /// .task once we've absorbed any restored data and migrated the
    /// lastCelebratedRank baseline.
    @State private var hasFinishedLaunchSync = false
    var body: some View {
        @Bindable var tabRouter = tabRouter
        TabView(selection: $tabRouter.selectedTab) {
            MapTabView()
                .tag(AppTab.map)
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tag(AppTab.browse)
                .tabItem { Label("Browse", systemImage: "fork.knife") }
            MyTiersView()
                .tag(AppTab.myTiers)
                .tabItem { Label("My Tiers", systemImage: "list.number") }
            CommunityTiersView()
                .tag(AppTab.community)
                .tabItem { Label("Community", systemImage: "person.3.fill") }
            ProfileView()
                .tag(AppTab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task {
            await cloudKit.refreshClosureCounts()
            // v1.5: mirror CloudKit's confirmed-closed set into the
            // store so Map + Browse drop closed spots from discovery.
            store.confirmedClosedIDs = cloudKit.confirmedClosedIDs
            // v1.5 (build 48): warm the Community/Pros tier caches in
            // the background. Fire-and-forget — the user can tap into
            // Community before this finishes and the existing stale-
            // while-revalidate cache still handles it; by the time
            // they DO tap, the cache is fresh and the in-tab refresh
            // is invisible.
            Task {
                await CommunityTiersView.prefetchCache(via: cloudKit)
            }
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
            pendingPostCelebrationRank = current
            lastCelebratedRank = current.displayName
        }
        .sheet(item: $celebratingRank, onDismiss: handlePostCelebration) { rank in
            RankCelebrationView(rank: rank, placementCount: tierStore.placements.count)
        }
        .sheet(isPresented: $showKofiSheet) {
            KofiSupportSheet()
        }
    }

    /// v1.5: fires after a rank-up celebration sheet dismisses. Drives
    /// the milestone-specific secondary prompts — review at Critic, Ko-fi
    /// at Connoisseur. Other tier-ups (Foodie, Tastemaker) get just the
    /// celebration and nothing else.
    private func handlePostCelebration() {
        guard let rank = pendingPostCelebrationRank else { return }
        pendingPostCelebrationRank = nil

        switch rank {
        case .critic where !hasSeenReviewPrompt:
            // Apple's native review prompt. Cap of 3/year is enforced
            // by the OS so even if we miscount, users aren't spammed.
            requestReview()
            hasSeenReviewPrompt = true
        case .connoisseur where !hasSeenKofiPrompt:
            showKofiSheet = true
            hasSeenKofiPrompt = true
        default:
            break
        }
    }
}
