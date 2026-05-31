import Foundation
import Observation

/// The set of dish-photo uploaders the current user has chosen to block.
/// Stored locally in UserDefaults — there's no need to round-trip blocks
/// through CloudKit (the effect we want is "I never see their photos again"
/// on this device, and a fresh install starts with an empty list).
///
/// Required by App Review Guideline 1.2: UGC apps must let users block
/// abusive contributors. Blocked uploaders' photos are filtered out of
/// `CloudKitService.fetchDishPhotos`.
@Observable
final class BlockListStore {
    private let defaultsKey = "WoodlandsEats.blockedUploaderIDs"
    private(set) var blocked: Set<String>

    init() {
        if let arr = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            blocked = Set(arr)
        } else {
            blocked = []
        }
    }

    func block(_ userID: String) {
        guard !userID.isEmpty else { return }
        blocked.insert(userID)
        persist()
    }

    func unblock(_ userID: String) {
        blocked.remove(userID)
        persist()
    }

    func isBlocked(_ userID: String?) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        return blocked.contains(userID)
    }

    private func persist() {
        UserDefaults.standard.set(Array(blocked), forKey: defaultsKey)
    }
}
