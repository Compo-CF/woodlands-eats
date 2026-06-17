import Foundation
import Observation

/// v1.2: per-restaurant "I've been here" tracking. Local-only — stored
/// as a Set<UUID> in UserDefaults under `WoodlandsEats.visitedRestaurantIDs`.
///
/// Why local-only and not CloudKit: "visited" is a personal record, not a
/// community signal. There's no aggregation across users (unlike Tier
/// placements which feed the consensus board), so it doesn't need to live
/// in the public DB. If cross-device sync becomes important later, the
/// upgrade path is similar to TierListStore.restoreFromCloud — add a
/// CloudKit record type and a hydrate-on-launch call. Defer until needed.
///
/// Resets on uninstall (UserDefaults is wiped). That's acceptable: visited
/// status is a personal convenience, not data the user would tier-rank.
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
