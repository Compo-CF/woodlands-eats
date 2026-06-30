import Foundation
import Observation

/// v1.2: per-restaurant "I've been here" tracking. Local cache in
/// UserDefaults under `WoodlandsEats.visitedRestaurantIDs`, synced to
/// CloudKit (single VisitedList record per user) for cross-device and
/// reinstall recovery.
///
/// Sync model (v1.3): the store stays unaware of CloudKit — view-layer
/// callers fire `cloudKit.saveVisitedList(visitedStore.visited)` in a
/// Task after each local mutation, matching the TierListStore pattern.
/// `restoreFromCloud(via:)` runs once at launch from ContentView.task
/// to hydrate after reinstall. No subscriptions / push — cross-device
/// updates land on next launch.
@Observable
final class VisitedStore {
    private let defaultsKey = "WoodlandsEats.visitedRestaurantIDs"
    private(set) var visited: Set<UUID>

    init() {
        if let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            visited = Set(raw.compactMap { UUID(uuidString: $0) })
        } else {
            visited = []
        }
    }

    /// Hydrate the local visited set from CloudKit. Fired once at app
    /// launch from ContentView.task. Mirrors TierListStore.restoreFromCloud.
    ///
    /// Guard: only restores when local is empty. If the user has been
    /// marking visits on this device already (possibly offline), we don't
    /// overwrite their in-progress work with stale CloudKit data.
    @MainActor
    func restoreFromCloud(via cloudKit: CloudKitService) async {
        guard visited.isEmpty else { return }
        let remote = await cloudKit.fetchVisitedList()
        guard !remote.isEmpty else { return }
        visited = remote
        persist()
    }

    /// v1.7 Feature G: additive cross-device sync. Called from ContentView
    /// when the scene becomes active. Picks up visits marked on another
    /// device (or while offline that synced later). Local-only marks are
    /// preserved — VisitedStore is a set so the merge is just union.
    @MainActor
    func mergeFromCloud(via cloudKit: CloudKitService) async {
        let remote = await cloudKit.fetchVisitedList()
        guard !remote.isEmpty else { return }
        let merged = visited.union(remote)
        guard merged != visited else { return }
        visited = merged
        persist()
    }

    /// v1.7 Feature I: one-time housekeeping. Drops local visited entries
    /// for restaurants no longer in the catalog (dedup-merged, removed).
    /// The VisitedList is a single CloudKit record per user so the next
    /// `saveVisitedList` write replaces the cloud copy with the cleaned set.
    @MainActor
    func cleanupOrphans(via cloudKit: CloudKitService, against restaurants: [Restaurant]) async {
        let validIDs = Set(restaurants.map(\.id))
        let cleaned = visited.intersection(validIDs)
        guard cleaned != visited else { return }
        visited = cleaned
        persist()
        await cloudKit.saveVisitedList(cleaned)
    }

    func isVisited(_ id: UUID) -> Bool {
        visited.contains(id)
    }

    func toggle(_ id: UUID) {
        if visited.contains(id) {
            visited.remove(id)
        } else {
            visited.insert(id)
        }
        persist()
    }

    func markVisited(_ id: UUID) {
        guard !visited.contains(id) else { return }
        visited.insert(id)
        persist()
    }

    func unmarkVisited(_ id: UUID) {
        guard visited.contains(id) else { return }
        visited.remove(id)
        persist()
    }

    var count: Int { visited.count }

    private func persist() {
        let asStrings = visited.map { $0.uuidString }
        UserDefaults.standard.set(asStrings, forKey: defaultsKey)
    }
}
