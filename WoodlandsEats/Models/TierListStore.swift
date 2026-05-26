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
