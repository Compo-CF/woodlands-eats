import Foundation
import Observation

/// The user's personal S/A/B/C/F placements, persisted on-device.
/// Phase 1 syncs these to CloudKit and aggregates everyone's lists into a
/// community consensus tier per restaurant.
@Observable
final class TierListStore {
    private(set) var placements: [UUID: Tier] = [:]

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("TierList.json")
    }

    init() {
        load()
    }

    /// Hydrate the local cache from CloudKit. Fired once at app launch from
    /// ContentView.task, AFTER the local `load()` runs in init.
    ///
    /// The bug this prevents: deleting and reinstalling the app (or
    /// restoring to a new device, or just upgrading via TestFlight after
    /// the local file got wiped) leaves the user with an empty "My Tiers"
    /// view even though their placements are still in CloudKit feeding
    /// the community board. Pre-build-36 behavior was local-cache-only,
    /// so any reinstall looked like total data loss to the user.
    ///
    /// Guard: only restores when local is empty. If the user has been
    /// ranking on this device already, we don't overwrite their in-progress
    /// work with stale CloudKit data. (Cross-device live sync is a v1.2+
    /// feature — would need CloudKit subscriptions for that.)
    @MainActor
    func restoreFromCloud(via cloudKit: CloudKitService) async {
        guard placements.isEmpty else { return }
        let remote = await cloudKit.fetchMyPlacements()
        guard !remote.isEmpty else { return }
        var restored: [UUID: Tier] = [:]
        for (rid, tier) in remote {
            restored[rid] = tier
        }
        placements = restored
        save()
    }

    /// v1.7 Feature G: additive cross-device sync. Called from ContentView
    /// when the scene becomes active (returning from background or another
    /// device). Unlike restoreFromCloud which only runs when local is empty,
    /// this merges CloudKit state on top of local — keeps any local-only
    /// in-flight changes that haven't synced yet, picks up new tiers /
    /// changed tiers from other devices.
    ///
    /// Conflict policy: CloudKit wins for restaurants both have (assumed
    /// already-synced). Local-only entries are preserved (in-flight saves
    /// that may not have reached CloudKit yet). Deletions on another device
    /// won't propagate via this path — they're rare and the user can clear
    /// the placement manually on the local device if needed.
    @MainActor
    func mergeFromCloud(via cloudKit: CloudKitService) async {
        let remote = await cloudKit.fetchMyPlacements()
        guard !remote.isEmpty else { return }
        var updated = placements
        for (rid, tier) in remote {
            updated[rid] = tier
        }
        guard updated != placements else { return }
        placements = updated
        save()
    }

    /// v1.7 Feature I: one-time housekeeping pass. Drops local placements
    /// for restaurants no longer in the catalog (dedup-merged across re-
    /// seeds, removed as non-restaurants, out-of-area), and deletes the
    /// corresponding CloudKit Placement records so the orphan doesn't
    /// leak into community aggregates.
    ///
    /// Called once per device via an @AppStorage flag in ContentView.
    /// Idempotent — re-running is safe; the second run finds nothing to do.
    @MainActor
    func cleanupOrphans(via cloudKit: CloudKitService, against restaurants: [Restaurant]) async {
        let validIDs = Set(restaurants.map(\.id))
        let orphans = placements.keys.filter { !validIDs.contains($0) }
        guard !orphans.isEmpty else { return }
        for rid in orphans {
            placements[rid] = nil
            // Fire-and-forget. If CloudKit deletion fails the orphan
            // stays in the public DB but is invisible to the user
            // (they have no local reference). Best-effort cleanup.
            await cloudKit.removePlacement(restaurantID: rid)
        }
        save()
    }

    func tier(for id: UUID) -> Tier? { placements[id] }

    func isRanked(_ id: UUID) -> Bool { placements[id] != nil }

    func setTier(_ tier: Tier, for id: UUID) {
        placements[id] = tier
        save()
    }

    func removeTier(for id: UUID) {
        placements[id] = nil
        save()
    }

    var rankedCount: Int { placements.count }

    /// Restaurants the user has placed in a given tier, ordered by name.
    func restaurants(in tier: Tier, from all: [Restaurant]) -> [Restaurant] {
        all.filter { placements[$0.id] == tier }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Persistence ([UUID:Tier] stored as [String:String] for readability)

    private func save() {
        let encodable = Dictionary(uniqueKeysWithValues:
            placements.map { ($0.key.uuidString, $0.value.rawValue) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        var result: [UUID: Tier] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key), let tier = Tier(rawValue: value) {
                result[id] = tier
            }
        }
        placements = result
    }
}
