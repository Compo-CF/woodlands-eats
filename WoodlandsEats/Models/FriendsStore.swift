import Foundation
import Observation

/// v2.0 Feature 3: one followed account. `userID` is the followee's opaque
/// iCloud user record name (same identifier used by placements + friend-tier
/// share links); `displayName` is a cached snapshot for offline list
/// rendering. Encoded as "userID|displayName" inside the FriendList record.
struct Friend: Identifiable, Hashable, Codable {
    let userID: String
    var displayName: String
    var id: String { userID }

    init(userID: String, displayName: String) {
        self.userID = userID
        self.displayName = displayName
    }

    /// Decode a "userID|displayName" record entry. Display names can contain
    /// "|" in theory, so split only on the FIRST separator.
    init?(encoded: String) {
        guard let sep = encoded.firstIndex(of: "|") else { return nil }
        let uid = String(encoded[encoded.startIndex..<sep])
        guard !uid.isEmpty else { return nil }
        self.userID = uid
        self.displayName = String(encoded[encoded.index(after: sep)...])
    }
}

/// v2.0 Feature 3: the persistent follow graph. Local cache in UserDefaults
/// under `WoodlandsEats.friends`, synced to CloudKit (single FriendList
/// record per user) for cross-device + reinstall recovery.
///
/// Sync model mirrors VisitedStore: the store owns local state and persists
/// to UserDefaults synchronously; each mutation fires a CloudKit write via
/// the injected service. `restoreFromCloud(via:)` hydrates once at launch.
/// A follow is directional and personal — no aggregation of the graph
/// itself, so last-write-wins is fine.
@Observable
final class FriendsStore {
    private let defaultsKey = "WoodlandsEats.friends"
    private(set) var friends: [Friend]

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        } else {
            friends = []
        }
    }

    var friendIDs: Set<String> { Set(friends.map(\.userID)) }
    var count: Int { friends.count }

    func isFollowing(_ userID: String) -> Bool {
        friends.contains { $0.userID == userID }
    }

    /// Hydrate from CloudKit at launch. Only when local is empty, so we don't
    /// clobber follows made on this device (possibly offline) with stale
    /// cloud data. Mirrors VisitedStore.restoreFromCloud.
    @MainActor
    func restoreFromCloud(via cloudKit: CloudKitService) async {
        guard friends.isEmpty else { return }
        let remote = await cloudKit.fetchFriendList()
        guard !remote.isEmpty else { return }
        friends = remote
        persist()
    }

    /// Follow a user. No-op (name refresh only) if already followed. Fires a
    /// CloudKit write. You can't follow yourself — the caller passes the
    /// current user's ID so we can guard it.
    @MainActor
    func follow(userID: String, displayName: String, myUserID: String, via cloudKit: CloudKitService) {
        let uid = userID.trimmingCharacters(in: .whitespaces)
        guard !uid.isEmpty, uid != myUserID else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = friends.firstIndex(where: { $0.userID == uid }) {
            guard !name.isEmpty, friends[idx].displayName != name else { return }
            friends[idx].displayName = name        // refresh cached name
        } else {
            friends.append(Friend(userID: uid, displayName: name.isEmpty ? "Foodie" : name))
        }
        persist()
        Task { await cloudKit.saveFriendList(friends) }
    }

    @MainActor
    func unfollow(userID: String, via cloudKit: CloudKitService) {
        guard friends.contains(where: { $0.userID == userID }) else { return }
        friends.removeAll { $0.userID == userID }
        persist()
        Task { await cloudKit.saveFriendList(friends) }
    }

    /// Account deletion (Guideline 5.1.1(v)): wipe the local follow graph.
    @MainActor
    func clearLocal() {
        friends = []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
