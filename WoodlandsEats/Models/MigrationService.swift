import Foundation
import SwiftUI

/// v1.6 (Android migration A3): one-time backfill of the current
/// user's CloudKit data into Firestore. Runs on first launch after
/// the v1.6 update; subsequent launches skip via @AppStorage flags.
///
/// Idempotent + resumable: each collection has its own completion
/// flag. If a launch is interrupted mid-migration, the next launch
/// resumes where it left off without re-doing completed steps.
///
/// Scope (v1.6 build 49):
///   - Placements (user's personal tier rankings) — CRITICAL
///   - Visited list (personal restaurant history) — CRITICAL
///   - Profile (display name + Foodie Pro status) — important
///
/// Out of scope for v1.6 backfill (handled in follow-up migrations):
///   - Closure reports the user submitted (low-value signal, easily
///     re-submitted)
///   - Photo reports (admin-side data, regenerable)
///   - Dish photos (Storage migration is a bigger workstream)
///   - LiveRestaurants (admin batch-write in a separate migration)
///   - Pro approvals (admin manually re-approves if needed)
///
/// The migration is gated by `FirebaseService.isReady`, so it waits
/// for anonymous Firebase Auth to resolve before attempting any
/// Firestore writes.
@Observable
final class MigrationService {
    // Persistence flags use UserDefaults directly because @AppStorage
    // is incompatible with @Observable's synthesized init accessors
    // (the macro can't see into a property wrapper's storage). Same
    // keys as before — UserDefaults backs @AppStorage anyway, so any
    // prior writes are still readable here.
    private let key_complete    = "WoodlandsEats.migration.v1.6.complete"
    private let key_placements  = "WoodlandsEats.migration.v1.6.placements"
    private let key_visited     = "WoodlandsEats.migration.v1.6.visited"
    private let key_profile     = "WoodlandsEats.migration.v1.6.profile"

    private var migrationComplete: Bool {
        get { UserDefaults.standard.bool(forKey: key_complete) }
        set { UserDefaults.standard.set(newValue, forKey: key_complete) }
    }
    private var placementsBackfilled: Bool {
        get { UserDefaults.standard.bool(forKey: key_placements) }
        set { UserDefaults.standard.set(newValue, forKey: key_placements) }
    }
    private var visitedBackfilled: Bool {
        get { UserDefaults.standard.bool(forKey: key_visited) }
        set { UserDefaults.standard.set(newValue, forKey: key_visited) }
    }
    private var profileBackfilled: Bool {
        get { UserDefaults.standard.bool(forKey: key_profile) }
        set { UserDefaults.standard.set(newValue, forKey: key_profile) }
    }

    /// Tracks whether a migration is currently in progress so it isn't
    /// re-entered from a concurrent .task launch.
    private(set) var isRunning = false

    /// Call from ContentView.task once Firebase auth has resolved.
    /// Returns immediately if no work is needed. Best-effort —
    /// failures are logged but don't block app function (CloudKit is
    /// still the authoritative read source).
    func runIfNeeded(
        cloudKit: CloudKitService,
        firebase: FirebaseService,
        tierStore: TierListStore,
        visitedStore: VisitedStore
    ) async {
        guard !migrationComplete else { return }
        guard !isRunning else { return }
        guard firebase.isReady else {
            // Firebase auth hasn't resolved yet. ContentView.task fires
            // restore/migration AFTER the launch refreshes, but auth is
            // async. If we're here too early, just return — the next
            // .task invocation (re-render) will try again. In practice
            // ContentView .task only runs once per app lifetime, so
            // bail-and-retry-next-launch is the safe fallback.
            print("[Migration] Firebase auth not ready, deferring to next launch")
            return
        }
        guard cloudKit.isAvailable else {
            print("[Migration] CloudKit not available — skipping backfill")
            return
        }

        isRunning = true
        defer { isRunning = false }

        print("[Migration] Starting v1.6 backfill — Firebase UID: \(firebase.userID ?? "nil")")

        // Step 1: placements
        if !placementsBackfilled {
            let placements = await cloudKit.fetchMyPlacements()
            print("[Migration] Backfilling \(placements.count) placements")
            for (restaurantID, tier) in placements {
                await firebase.savePlacement(restaurantID: restaurantID, tier: tier)
            }
            placementsBackfilled = true
            print("[Migration] Placements complete")
        }

        // Step 2: visited list. Use the local VisitedStore as authoritative —
        // it was already restored from CloudKit by tierStore-style flow in
        // ContentView.task before MigrationService runs.
        if !visitedBackfilled {
            let visited = visitedStore.visited
            print("[Migration] Backfilling \(visited.count) visited restaurants")
            if !visited.isEmpty {
                await firebase.saveVisitedList(visited)
            }
            visitedBackfilled = true
            print("[Migration] Visited complete")
        }

        // Step 3: profile. Only backfill if a profile actually exists in
        // CloudKit (avoid creating empty Firestore profile docs for users
        // who never set a display name).
        if !profileBackfilled {
            let profile = await cloudKit.fetchMyProfile()
            if !profile.displayName.isEmpty || !profile.status.isEmpty {
                let isApproved = await cloudKit.amIApproved()
                let status = isApproved ? "approved" : profile.status
                print("[Migration] Backfilling profile: \(profile.displayName) (\(status))")
                await firebase.saveProfile(displayName: profile.displayName, status: status)
            }
            profileBackfilled = true
            print("[Migration] Profile complete")
        }

        migrationComplete = true
        print("[Migration] v1.6 backfill complete for Firebase UID: \(firebase.userID ?? "nil")")
    }
}
