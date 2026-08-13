import Foundation
import CloudKit
import Observation

/// Aggregated community ranking for a restaurant: everyone's tier placements
/// averaged into a consensus tier, plus how many people contributed.
struct CommunityTier {
    let tier: Tier
    let count: Int
    let average: Double
}

/// A user-submitted dish photo for a restaurant (CloudKit CKAsset, downloaded).
/// `submitterUserID` is the uploader's iCloud user record name (recorded on
/// the photo record from build 14 onward). Used to filter blocked uploaders
/// client-side. May be nil for legacy photos uploaded before build 14.
struct DishPhoto: Identifiable {
    let id: String
    let caption: String?
    let imageData: Data
    let submitterUserID: String?
}

/// v2.0 Feature 2: one community member's note on a restaurant — the "why"
/// behind their tier placement. Stored in the `note` field of their Placement
/// record; `placementRecordName` doubles as the stable identity and the
/// moderation target (report / admin-hide). `authorUserID` drives block-list
/// filtering; `tier` is the author's own placement, shown as context.
struct CommunityNote: Identifiable {
    let placementRecordName: String
    let authorUserID: String?
    let text: String
    let tier: Tier?
    var id: String { placementRecordName }
}

/// v2.1: one recent ranking action by someone the user follows, for the
/// Friend Activity feed. `date` is the placement's last-modified time.
struct FriendActivity: Identifiable {
    let placementRecordName: String
    let authorUserID: String
    let restaurantID: UUID
    let tier: Tier
    let date: Date
    var id: String { placementRecordName }
}

/// v2.0 Feature 2: a reported note hydrated for the admin queue.
struct PendingNoteReport: Identifiable {
    let placementRecordName: String
    let authorUserID: String?
    let text: String
    var id: String { placementRecordName }
}

/// A user-submitted report flagging a dish photo as objectionable
/// (admin moderation queue, App Review Guideline 1.2).
struct PhotoReport: Identifiable {
    let id: String          // PhotoReport recordName
    let photoID: String     // DishPhoto recordName
    let reporterID: String
}

/// A user's Foodie Pro request (their FoodieProfile), for the admin approval UI.
/// v1.7 Feature B+: `isAppleVerified` surfaces an Apple-signed-in badge
/// in the admin's approved Pros list so identity verification is one
/// fewer thing the admin has to track manually.
struct ProRequest: Identifiable {
    let id: String          // FoodieProfile recordName
    let displayName: String
    let userID: String
    let isAppleVerified: Bool
}

/// A user-submitted "missing restaurant" suggestion awaiting admin approval.
struct Suggestion: Identifiable {
    let id: String          // RestaurantSuggestion recordName
    let name: String
    let address: String
    let area: String
    let cuisines: [String]
    let description: String
    let submitterUserID: String
}

/// Thin wrapper over the CloudKit public database for the crowdsourcing layer.
///
/// Identity is implicit: CloudKit attributes each record to the signed-in iCloud
/// account, and we key one placement record per (user, restaurant) so re-ranking
/// upserts. No Sign in with Apple needed for the MVP.
///
/// Everything degrades gracefully: if there's no iCloud account, the container
/// isn't configured yet, or the network is down, `isAvailable` stays false and
/// every method is a no-op — the app keeps running on local data only. This is
/// why the project still builds and runs before the CloudKit capability is added
/// on the Mac.
@Observable
final class CloudKitService {
    private(set) var isAvailable = false

    private let container = CKContainer.default()
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var cachedUserRecordName: String?

    private let placementType = "Placement"
    private let closureType = "ClosureReport"
    private let profileType = "FoodieProfile"
    private let approvalType = "ProApproval"
    private let suggestionType = "RestaurantSuggestion"
    private let liveType = "LiveRestaurant"
    private let dismissalType = "SuggestionDismissed"
    private let photoType = "DishPhoto"
    private let photoReportType = "PhotoReport"
    /// v2.0 Feature 2: report of an objectionable placement note. recordName
    /// `noteReport_<reporter>_<placementRecordName>`, idempotent per reporter.
    /// The reported note lives inside the Placement record (`note` field), so
    /// the report stores the owning placement's recordName as `placementName`.
    private let noteReportType = "NoteReport"
    /// v2.4: community dietary/needs tags. One record per (user, restaurant,
    /// tag) so confirmations dedupe + count. recordName
    /// `diet_<user>_<restaurant>_<tag>`. Fields: restaurantID (queryable),
    /// tag, userID.
    private let dietaryTagType = "DietaryTag"
    /// v1.3: per-user "I've been here" list. Single record per user with
    /// the whole restaurant-id set as an array — chosen over per-restaurant
    /// records because the data is purely personal (no community
    /// aggregation), small (a few hundred UUIDs max), and last-write-wins
    /// is fine for the rare cross-device conflict.
    private let visitedType = "VisitedList"
    /// v2.0 Feature 3: the user's follow graph. One record per user holding
    /// the followed accounts as an array of "userID|displayName" strings.
    /// Purely personal (no community aggregation of the graph itself),
    /// small, last-write-wins — same rationale as VisitedList.
    private let friendListType = "FriendList"
    /// v1.3.1: admin's verdict on a restaurant's closure status. One
    /// record per restaurant, admin-owned (like PhotoModerated). Field
    /// `decision` is "closed" or "open". Browse strikethrough + detail-
    /// view closure banner gate on decision=="closed" — raw user reports
    /// no longer surface across the app until admin verifies.
    private let closureDecisionType = "ClosureDecision"
    /// Admin-owned per-photo decision marker. recordName: `photoMod_<photoID>`.
    /// Field `decision` is "hidden" or "approved" — hidden photos are filtered
    /// out of `fetchDishPhotos` for everyone; approved photos drop out of the
    /// admin queue but stay visible.
    private let photoModType = "PhotoModerated"
    /// v1.8: admin-owned integrity remediation marker. recordName
    /// `excl_<kind>_<target>`; kind "user" bans an account's votes,
    /// kind "placement" masks one rating. See the Admin exclusions MARK.
    private let exclusionType = "AdminExclusion"
    /// iCloud user record names allowed to approve Foodie Pros (shown on the Profile tab).
    private let adminUserIDs: Set<String> = ["_e8b0bfe996b6e232421afac393ab8a3b"]

    /// Per-restaurant count of "permanently closed" reports; refreshed on launch
    /// and after a report toggle. Read by the list + map to flag closed spots.
    private(set) var closureCounts: [UUID: Int] = [:]
    /// v1.3.1: admin-confirmed-closed restaurant IDs. Browse strikethrough
    /// and the detail-view closure banner gate on this set rather than on
    /// raw closureCounts, so user reports stay informational until the
    /// admin actively verifies. Refreshed alongside closureCounts.
    private(set) var confirmedClosedIDs: Set<UUID> = []

    init() {
        Task { await refreshAvailability() }
    }

    @MainActor
    func refreshAvailability() async {
        do {
            isAvailable = try await container.accountStatus() == .available
        } catch {
            isAvailable = false
        }
    }

    private func userRecordName() async -> String? {
        if let cachedUserRecordName { return cachedUserRecordName }
        let name = try? await container.userRecordID().recordName
        cachedUserRecordName = name
        return name
    }

    private func placementRecordID(user: String, restaurant: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "placement_\(user)_\(restaurant.uuidString)")
    }

    /// Upsert this user's tier placement for a restaurant.
    ///
    /// v2.0 Feature 2: read-modify-write so changing the tier preserves
    /// any existing `note`. When `note` is provided it's written (empty
    /// string clears it); when nil the existing note is left untouched.
    /// The extra fetch is one record(for:) by known ID — cheap.
    func savePlacement(restaurantID: UUID, tier: Tier, note: String? = nil) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let id = placementRecordID(user: user, restaurant: restaurantID)
        let record = (try? await publicDB.record(for: id))
            ?? CKRecord(recordType: placementType, recordID: id)
        record["restaurantID"] = restaurantID.uuidString as CKRecordValue
        record["tier"] = tier.rawValue as CKRecordValue
        record["score"] = tier.score as CKRecordValue
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            record["note"] = trimmed.isEmpty ? nil : (trimmed as CKRecordValue)
        }
        _ = try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        // Android migration: mirror to Firestore (fire-and-forget).
        Task { await FirebaseService.shared.savePlacement(restaurantID: restaurantID, tier: tier, note: note) }
    }

    /// v2.0 Feature 2: set/clear ONLY the note on the user's existing
    /// placement (used by the "add a note" field once a tier is set).
    func saveMyNote(restaurantID: UUID, note: String) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let id = placementRecordID(user: user, restaurant: restaurantID)
        // No-op if the user hasn't placed this restaurant yet (a note
        // requires a tier — enforced in the UI, guarded here too).
        guard let record = try? await publicDB.record(for: id) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record["note"] = trimmed.isEmpty ? nil : (trimmed as CKRecordValue)
        _ = try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        Task { await FirebaseService.shared.saveNote(restaurantID: restaurantID, note: note) }
    }

    func removePlacement(restaurantID: UUID) async {
        guard isAvailable, let user = await userRecordName() else { return }
        _ = try? await publicDB.modifyRecords(
            saving: [],
            deleting: [placementRecordID(user: user, restaurant: restaurantID)],
            savePolicy: .allKeys)
        Task { await FirebaseService.shared.removePlacement(restaurantID: restaurantID) }
    }

    // MARK: - Dietary tags (v2.4)

    private func dietaryTagRecordID(user: String, restaurant: UUID, tag: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "diet_\(user)_\(restaurant.uuidString)_\(tag)")
    }

    /// Add or remove this user's confirmation of a dietary tag for a
    /// restaurant. `tag` is the DietaryTag raw value.
    func setDietaryTag(restaurantID: UUID, tag: String, on: Bool) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let id = dietaryTagRecordID(user: user, restaurant: restaurantID, tag: tag)
        if on {
            let record = (try? await publicDB.record(for: id))
                ?? CKRecord(recordType: dietaryTagType, recordID: id)
            record["restaurantID"] = restaurantID.uuidString as CKRecordValue
            record["tag"] = tag as CKRecordValue
            record["userID"] = user as CKRecordValue
            _ = try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } else {
            _ = try? await publicDB.modifyRecords(saving: [], deleting: [id], savePolicy: .allKeys)
        }
        Task { await FirebaseService.shared.setDietaryTag(restaurantID: restaurantID, tag: tag, on: on) }
    }

    /// Community dietary tags for a restaurant: count per tag, plus the set
    /// of tags the current user has personally confirmed. Both keyed by the
    /// DietaryTag raw value. Returns empties on any failure path.
    func fetchDietaryTags(restaurantID: UUID) async -> (counts: [String: Int], mine: Set<String>) {
        guard isAvailable else { return ([:], []) }
        let me = await userRecordName()
        var counts: [String: Int] = [:]
        var mine: Set<String> = []
        let keys = ["tag", "userID"]
        let pred = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: dietaryTagType, predicate: pred)

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                guard case .success(let rec) = result,
                      let tag = rec["tag"] as? String else { continue }
                counts[tag, default: 0] += 1
                if let uid = rec["userID"] as? String, uid == me { mine.insert(tag) }
            }
        }

        do {
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: keys, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return ([:], [])
        }
        return (counts, mine)
    }

    /// Fetch all of this user's tier placements from CloudKit.
    ///
    /// Used by TierListStore.restoreFromCloud(via:) at launch to hydrate
    /// the local cache after a reinstall or device restore — otherwise the
    /// user's "My Tiers" view appears empty even though their placements
    /// are still in CloudKit feeding the community consensus.
    ///
    /// Implementation: pages through all Placement records and filters
    /// client-side by recordName prefix `placement_<userID>_`. The
    /// recordName index is queryable for equality but CloudKit doesn't
    /// support BEGINSWITH on recordName, so client-side filtering is the
    /// pragmatic move. At early-app scale (sub-thousand placements
    /// total in the public DB) the overhead is negligible.
    ///
    /// Returns [] on any failure path so callers can no-op gracefully.
    func fetchMyPlacements() async -> [(restaurantID: UUID, tier: Tier)] {
        guard isAvailable, let user = await userRecordName() else { return [] }
        return await fetchPlacements(forUserID: user)
    }

    /// v1.7 (Feature C): fetch any user's placements by their userRecordName.
    /// Used by the friend-tier-link flow — a user shares a URL containing
    /// their userRecordName, the recipient's app calls this to render the
    /// shared tier list read-only. Same client-side prefix-filter pattern
    /// as `fetchMyPlacements`.
    func fetchPlacements(forUserID user: String) async -> [(restaurantID: UUID, tier: Tier)] {
        guard isAvailable, !user.isEmpty else { return [] }
        let prefix = "placement_\(user)_"
        var out: [(restaurantID: UUID, tier: Tier)] = []

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                guard recordID.recordName.hasPrefix(prefix) else { continue }
                guard case .success(let rec) = result else { continue }
                guard let ridStr = rec["restaurantID"] as? String,
                      let rid = UUID(uuidString: ridStr),
                      let tierStr = rec["tier"] as? String,
                      let tier = Tier(rawValue: tierStr) else { continue }
                out.append((rid, tier))
            }
        }

        do {
            let query = CKQuery(recordType: placementType,
                                predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query,
                desiredKeys: ["restaurantID", "tier"],
                resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            // CloudKit unavailable / network error / index missing — return
            // what we accumulated (possibly nothing). The TierListStore
            // caller falls through to local cache.
        }
        return out
    }

    // MARK: - Visited list (v1.3 — personal "I've been here" sync)

    private func visitedRecordID(user: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "visited_\(user)")
    }

    /// Save the user's entire visited-restaurant set to CloudKit.
    /// Single record per user, overwritten on every change — small payload
    /// (a few hundred UUIDs max) and last-write-wins is acceptable for
    /// a personal flag with no community aggregation.
    /// Fired from RestaurantDetailView after each local toggle.
    func saveVisitedList(_ ids: Set<UUID>) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let record = CKRecord(recordType: visitedType,
                              recordID: visitedRecordID(user: user))
        record["restaurantIDs"] = ids.map { $0.uuidString } as CKRecordValue
        record["count"] = ids.count as CKRecordValue
        _ = try? await publicDB.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        Task { await FirebaseService.shared.saveVisitedList(ids) }
    }

    /// Fetch the user's visited-restaurant set from CloudKit. Used by
    /// VisitedStore.restoreFromCloud at launch to hydrate after a fresh
    /// install / device restore — otherwise the user's visited badges
    /// would silently disappear on reinstall even though the data is
    /// still in CloudKit.
    ///
    /// Returns [] gracefully on any failure (no iCloud account, no
    /// record yet, network error). Direct record(for:) — no index needed.
    func fetchVisitedList() async -> Set<UUID> {
        guard isAvailable, let user = await userRecordName() else { return [] }
        do {
            let rec = try await publicDB.record(for: visitedRecordID(user: user))
            guard let ids = rec["restaurantIDs"] as? [String] else { return [] }
            return Set(ids.compactMap { UUID(uuidString: $0) })
        } catch {
            return []
        }
    }

    // MARK: - Friends / follow graph (v2.0 Feature 3)

    private func friendListRecordID(user: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "friends_\(user)")
    }

    /// Persist the user's entire follow list. Single record per user,
    /// overwritten each change — mirrors saveVisitedList. Each friend is
    /// encoded "userID|displayName"; the display name is a cached snapshot
    /// for offline list rendering (the authoritative name still comes from
    /// the followee's FoodieProfile when their tier list is opened).
    func saveFriendList(_ friends: [Friend]) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let record = CKRecord(recordType: friendListType,
                              recordID: friendListRecordID(user: user))
        let entries = friends.map { "\($0.userID)|\($0.displayName)" }
        record["entries"] = entries as CKRecordValue
        record["count"] = friends.count as CKRecordValue
        _ = try? await publicDB.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        Task { await FirebaseService.shared.saveFriendList(entries) }
    }

    /// Fetch the user's follow list. Returns [] on any failure. Direct
    /// record(for:) — no index needed.
    func fetchFriendList() async -> [Friend] {
        guard isAvailable, let user = await userRecordName() else { return [] }
        do {
            let rec = try await publicDB.record(for: friendListRecordID(user: user))
            guard let entries = rec["entries"] as? [String] else { return [] }
            return entries.compactMap { Friend(encoded: $0) }
        } catch {
            return []
        }
    }

    /// Aggregate the placements of ONLY the given friend user IDs into a
    /// per-restaurant consensus tier — the "Friends" board. Reuses the same
    /// TRUEPREDICATE walk as fetchAllCommunityTiers but keeps a placement
    /// only if its owner is in `friendIDs`. Admin exclusions still apply.
    /// Returns [:] if the friend set is empty or CloudKit is unavailable.
    func fetchFriendsCommunityTiers(friendIDs: Set<String>) async -> [UUID: CommunityTier] {
        guard isAvailable, !friendIDs.isEmpty else { return [:] }
        await loadExclusionsIfNeeded()
        var sums: [UUID: (total: Int, count: Int)] = [:]
        let keys = ["restaurantID", "score"]

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                let owner = placementOwnerID(from: recordID.recordName)
                guard let owner, friendIDs.contains(owner) else { continue }
                guard case .success(let rec) = result,
                      let ridStr = rec["restaurantID"] as? String,
                      let rid = UUID(uuidString: ridStr),
                      let score = rec["score"] as? Int,
                      !isExcluded(recordName: recordID.recordName, owner: owner)
                else { continue }
                var e = sums[rid] ?? (0, 0)
                e.total += score; e.count += 1
                sums[rid] = e
            }
        }
        do {
            let query = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: keys, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return [:]
        }
        var out: [UUID: CommunityTier] = [:]
        for (rid, e) in sums where e.count > 0 {
            let avg = Double(e.total) / Double(e.count)
            out[rid] = CommunityTier(tier: .from(averageScore: avg), count: e.count, average: avg)
        }
        return out
    }

    // MARK: - Account deletion (App Review Guideline 5.1.1(v))

    /// Delete every CloudKit record this user created — their account
    /// (FoodieProfile) and all associated data (placements + notes, visited
    /// list, follow graph, dish photos, suggestions, and their own reports).
    ///
    /// Admin-owned records (ProApproval, AdminExclusion, PhotoModerated,
    /// ClosureDecision, LiveRestaurant) are NOT the user's and are left
    /// intact — the public DB wouldn't let a normal user delete them anyway.
    ///
    /// Best-effort per type: one type failing (e.g. transient error) doesn't
    /// abort the rest. Returns false only if there's no iCloud user to act on.
    func deleteMyAccount() async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }

        // 1. Direct deletes by known recordName — no query required.
        let direct: [CKRecord.ID] = [
            profileRecordID(user: user),
            visitedRecordID(user: user),
            friendListRecordID(user: user),
        ]
        _ = try? await publicDB.modifyRecords(saving: [], deleting: direct, savePolicy: .allKeys)

        // 2. Types whose recordName encodes the userID — page + prefix-match.
        //    (note: deleting a Placement removes its embedded note too.)
        await deleteByRecordNamePrefix(type: placementType, prefix: "placement_\(user)_")
        await deleteByRecordNamePrefix(type: closureType, prefix: "closure_\(user)_")
        await deleteByRecordNamePrefix(type: photoReportType, prefix: "photoReport_\(user)_")
        await deleteByRecordNamePrefix(type: noteReportType, prefix: "noteReport_\(user)_")

        // 3. Types that store the owner in a field — page + field-match.
        await deleteByField(type: photoType, field: "submitterUserID", equals: user)
        await deleteByField(type: suggestionType, field: "submitterUserID", equals: user)

        return true
    }

    /// Page a record type and delete every record whose recordName begins
    /// with `prefix`. Needs a Queryable recordName index on the type (all
    /// four callers have one). Swallows errors — best-effort.
    private func deleteByRecordNamePrefix(type: String, prefix: String) async {
        var toDelete: [CKRecord.ID] = []
        func collect(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (id, _) in matches where id.recordName.hasPrefix(prefix) {
                toDelete.append(id)
            }
        }
        do {
            let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: q, desiredKeys: [], resultsLimit: 200)
            collect(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                collect(matches)
            }
        } catch { return }
        await deleteInBatches(toDelete)
    }

    /// Page a record type and delete every record whose `field` equals `value`.
    private func deleteByField(type: String, field: String, equals value: String) async {
        var toDelete: [CKRecord.ID] = []
        func collect(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (id, result) in matches {
                if case .success(let rec) = result, rec[field] as? String == value {
                    toDelete.append(id)
                }
            }
        }
        do {
            let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: q, desiredKeys: [field], resultsLimit: 200)
            collect(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                collect(matches)
            }
        } catch { return }
        await deleteInBatches(toDelete)
    }

    /// Delete record IDs in chunks (CloudKit caps records per modify op).
    private func deleteInBatches(_ ids: [CKRecord.ID]) async {
        guard !ids.isEmpty else { return }
        var i = 0
        while i < ids.count {
            let batch = Array(ids[i..<min(i + 300, ids.count)])
            _ = try? await publicDB.modifyRecords(saving: [], deleting: batch, savePolicy: .allKeys)
            i += 300
        }
    }

    /// v2.1: recent ranking activity from the people the user follows, newest
    /// first, capped. Pages Placement (reusing the recordName Queryable index),
    /// keeps only records owned by a followed user, and stamps each with the
    /// placement's last-modified date. Admin exclusions are honored.
    func fetchFriendActivity(friendIDs: Set<String>, limit: Int = 60) async -> [FriendActivity] {
        guard isAvailable, !friendIDs.isEmpty else { return [] }
        await loadExclusionsIfNeeded()
        var out: [FriendActivity] = []

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                let name = recordID.recordName
                guard let owner = placementOwnerID(from: name), friendIDs.contains(owner),
                      !isExcluded(recordName: name, owner: owner),
                      case .success(let rec) = result,
                      let ridStr = rec["restaurantID"] as? String, let rid = UUID(uuidString: ridStr),
                      let tierStr = rec["tier"] as? String, let tier = Tier(rawValue: tierStr) else { continue }
                out.append(FriendActivity(
                    placementRecordName: name,
                    authorUserID: owner,
                    restaurantID: rid,
                    tier: tier,
                    date: rec.modificationDate ?? rec.creationDate ?? .distantPast))
            }
        }

        do {
            let query = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["restaurantID", "tier"], resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return []
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Average everyone's placements for a restaurant into a consensus tier.
    /// Returns nil if no one has ranked it yet (or CloudKit is unavailable).
    func fetchCommunityTier(restaurantID: UUID) async -> CommunityTier? {
        guard isAvailable else { return nil }
        await loadExclusionsIfNeeded()
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: placementType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 500)
            let scores: [Int] = results.compactMap { recordID, result in
                // v1.8: skip admin-excluded ratings / banned users.
                guard !isExcluded(recordName: recordID.recordName,
                                  owner: placementOwnerID(from: recordID.recordName))
                else { return nil }
                if case .success(let rec) = result { return rec["score"] as? Int }
                return nil
            }
            guard !scores.isEmpty else { return nil }
            let avg = Double(scores.reduce(0, +)) / Double(scores.count)
            return CommunityTier(tier: .from(averageScore: avg), count: scores.count, average: avg)
        } catch {
            return nil
        }
    }

    /// Aggregate EVERY placement across all users into a per-restaurant community
    /// tier (for the Community board). Pages through the public DB. Requires a
    /// Queryable index on the Placement record's `recordName` (for the fetch-all
    /// TRUEPREDICATE query); returns [:] gracefully until that exists.
    func fetchAllCommunityTiers() async -> [UUID: CommunityTier] {
        guard isAvailable else { return [:] }
        await loadExclusionsIfNeeded()
        var sums: [UUID: (total: Int, count: Int)] = [:]
        let keys = ["restaurantID", "score"]

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                guard case .success(let rec) = result,
                      let ridStr = rec["restaurantID"] as? String,
                      let rid = UUID(uuidString: ridStr),
                      let score = rec["score"] as? Int,
                      // v1.8: skip admin-excluded ratings / banned users.
                      !isExcluded(recordName: recordID.recordName,
                                  owner: placementOwnerID(from: recordID.recordName))
                else { continue }
                var entry = sums[rid] ?? (0, 0)
                entry.total += score
                entry.count += 1
                sums[rid] = entry
            }
        }

        do {
            let query = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: keys, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return [:]
        }

        var out: [UUID: CommunityTier] = [:]
        for (rid, agg) in sums where agg.count > 0 {
            let avg = Double(agg.total) / Double(agg.count)
            out[rid] = CommunityTier(tier: .from(averageScore: avg), count: agg.count, average: avg)
        }
        return out
    }

    /// v1.8 (integrity audit): fetch every Placement with the metadata
    /// AuditService needs — owner (parsed from recordName), restaurantID,
    /// tier, creationDate. Admin-only in the UI; the network call is
    /// gated by the admin check in ProfileView, not by CloudKit itself
    /// (public DB read is available to all authed users, we just don't
    /// surface the button for non-admins).
    ///
    /// Cost: same TRUEPREDICATE page-through as fetchAllCommunityTiers
    /// — one full walk. Returns [] on any error path.
    func fetchAllPlacementsForAudit() async -> [AuditPlacement] {
        guard isAvailable else { return [] }
        let keys = ["restaurantID", "tier"]
        var out: [AuditPlacement] = []

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                guard case .success(let rec) = result,
                      let ridStr = rec["restaurantID"] as? String,
                      let rid = UUID(uuidString: ridStr),
                      let tierStr = rec["tier"] as? String,
                      let tier = Tier(rawValue: tierStr),
                      let owner = placementOwnerID(from: recordID.recordName),
                      let created = rec.creationDate
                else { continue }
                out.append(AuditPlacement(
                    recordName: recordID.recordName,
                    userID: owner,
                    restaurantID: rid,
                    tier: tier,
                    creationDate: created
                ))
            }
        }

        do {
            let query = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: keys, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return []
        }
        return out
    }

    /// v1.8 (dashboard): count all FoodieProfile records. FoodieProfile
    /// has no recordName Queryable index, so TRUEPREDICATE fails — we
    /// bucket by the Queryable `status` field instead (every profile is
    /// written with one of these three values by saveProfile).
    func fetchProfileCount() async -> Int {
        guard isAvailable else { return 0 }
        var count = 0
        for statusValue in ["", "requested", "approved"] {
            do {
                let query = CKQuery(
                    recordType: profileType,
                    predicate: NSPredicate(format: "status == %@", statusValue))
                var (matches, cursor) = try await publicDB.records(
                    matching: query, desiredKeys: [], resultsLimit: 400)
                count += matches.count
                while let c = cursor {
                    (matches, cursor) = try await publicDB.records(
                        continuingMatchFrom: c, resultsLimit: 400)
                    count += matches.count
                }
            } catch {
                // Partial counts acceptable.
            }
        }
        return count
    }

    // MARK: - Admin exclusions (v1.8 integrity remediation)
    //
    // CloudKit public DB only lets a record's CREATOR modify or delete
    // it — the admin cannot delete another user's Placement. Remediation
    // therefore follows the same admin-owned-override pattern as
    // PhotoModerated / ClosureDecision: the admin writes an
    // `AdminExclusion` record and every client filters against it when
    // computing community aggregates.
    //
    //   kind = "user"      → target = userID; ALL of that user's
    //                        placements stop counting (ban)
    //   kind = "placement" → target = placement recordName; that single
    //                        rating stops counting
    //
    // The excluded user still sees their own My Tiers locally (their
    // records are untouched) — their votes just no longer influence
    // the community consensus anyone sees.
    //
    // CloudKit schema REQUIRED before this works in TestFlight/App Store:
    //   Dashboard → Development → Record Types → new type `AdminExclusion`
    //   with String fields `kind` + `target`, then Indexes → add
    //   Queryable index on AdminExclusion recordName (needed for the
    //   TRUEPREDICATE fetch below), then Deploy Schema Changes → Production.
    //   Until deployed, fetchExclusions returns empty and the app behaves
    //   exactly as before.

    /// Cached exclusion sets. Loaded once per launch on first community
    /// aggregate; force-refreshed after every admin ban/unban action.
    private(set) var bannedUserIDs: Set<String> = []
    private(set) var excludedPlacementNames: Set<String> = []
    /// v2.0 Feature 2: placement recordNames whose NOTE (not the rating) the
    /// admin has hidden. The placement's tier still counts in aggregates; only
    /// its note text is suppressed everywhere. kind="note" in AdminExclusion.
    private(set) var hiddenNoteNames: Set<String> = []
    private var exclusionsLoaded = false

    private func exclusionRecordID(kind: String, target: String) -> CKRecord.ID {
        // recordName must be ≤255 chars; userIDs (~32) and placement
        // recordNames (~80) are well under even with the prefix.
        CKRecord.ID(recordName: "excl_\(kind)_\(target)")
    }

    /// Page all AdminExclusion records into the cached sets.
    func loadExclusionsIfNeeded(force: Bool = false) async {
        guard isAvailable, force || !exclusionsLoaded else { return }
        var banned: Set<String> = []
        var removed: Set<String> = []
        var hiddenNotes: Set<String> = []
        do {
            let query = CKQuery(recordType: exclusionType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["kind", "target"], resultsLimit: 200)
            func accumulate(_ ms: [(CKRecord.ID, Result<CKRecord, Error>)]) {
                for (_, result) in ms {
                    guard case .success(let rec) = result,
                          let kind = rec["kind"] as? String,
                          let target = rec["target"] as? String else { continue }
                    if kind == "user" { banned.insert(target) }
                    else if kind == "placement" { removed.insert(target) }
                    else if kind == "note" { hiddenNotes.insert(target) }
                }
            }
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
            bannedUserIDs = banned
            excludedPlacementNames = removed
            hiddenNoteNames = hiddenNotes
            exclusionsLoaded = true
        } catch {
            // Schema not deployed yet or transient error — leave the
            // caches as-is (empty on first launch). Aggregates fall back
            // to unfiltered behavior, identical to pre-v1.8.
        }
    }

    /// True if a placement should be masked out of community aggregates.
    private func isExcluded(recordName: String, owner: String?) -> Bool {
        if excludedPlacementNames.contains(recordName) { return true }
        if let owner, bannedUserIDs.contains(owner) { return true }
        return false
    }

    /// Admin: ban a user — all their placements stop counting everywhere.
    @discardableResult
    func banUser(userID: String) async -> Bool {
        guard isAvailable, await isAdmin(), !userID.isEmpty else { return false }
        let rec = CKRecord(recordType: exclusionType,
                           recordID: exclusionRecordID(kind: "user", target: userID))
        rec["kind"] = "user" as CKRecordValue
        rec["target"] = userID as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            bannedUserIDs.insert(userID)
            Task { await FirebaseService.shared.saveExclusion(kind: "user", target: userID) }
            return true
        } catch { return false }
    }

    /// Admin: lift a ban (deletes the admin-owned exclusion record —
    /// allowed because the admin created it).
    @discardableResult
    func unbanUser(userID: String) async -> Bool {
        guard isAvailable, await isAdmin() else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [], deleting: [exclusionRecordID(kind: "user", target: userID)],
                savePolicy: .allKeys)
            bannedUserIDs.remove(userID)
            Task { await FirebaseService.shared.deleteExclusion(kind: "user", target: userID) }
            return true
        } catch { return false }
    }

    /// Admin: exclude one specific rating from community aggregates.
    @discardableResult
    func excludePlacement(recordName: String) async -> Bool {
        guard isAvailable, await isAdmin(), !recordName.isEmpty else { return false }
        let rec = CKRecord(recordType: exclusionType,
                           recordID: exclusionRecordID(kind: "placement", target: recordName))
        rec["kind"] = "placement" as CKRecordValue
        rec["target"] = recordName as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            excludedPlacementNames.insert(recordName)
            Task { await FirebaseService.shared.saveExclusion(kind: "placement", target: recordName) }
            return true
        } catch { return false }
    }

    /// Admin: restore a previously-excluded rating.
    @discardableResult
    func restorePlacement(recordName: String) async -> Bool {
        guard isAvailable, await isAdmin() else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [], deleting: [exclusionRecordID(kind: "placement", target: recordName)],
                savePolicy: .allKeys)
            excludedPlacementNames.remove(recordName)
            Task { await FirebaseService.shared.deleteExclusion(kind: "placement", target: recordName) }
            return true
        } catch { return false }
    }

    // MARK: - Placement notes (v2.0 Feature 2 — the "why")

    /// Fetch the community's notes for one restaurant. Piggybacks on the same
    /// per-restaurant Placement query the detail view already runs for the
    /// community tier, so no extra round-trip is needed at the call site if it
    /// reuses this. Applies the same three moderation layers as photos:
    ///   • notes on admin-excluded placements / banned users are dropped
    ///   • notes the admin has individually hidden (kind="note") are dropped
    ///   • notes from uploaders in the viewer's local block list are dropped
    /// The viewer's own note is excluded here (the UI shows it in the editor).
    func fetchCommunityNotes(restaurantID: UUID,
                             blockedUserIDs: Set<String> = []) async -> [CommunityNote] {
        guard isAvailable else { return [] }
        await loadExclusionsIfNeeded()
        let me = await userRecordName()
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: placementType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 500)
            var notes: [CommunityNote] = []
            for (recordID, result) in results {
                guard case .success(let rec) = result,
                      let text = (rec["note"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                let name = recordID.recordName
                let owner = placementOwnerID(from: name)
                if isExcluded(recordName: name, owner: owner) { continue }
                if hiddenNoteNames.contains(name) { continue }
                if let owner, blockedUserIDs.contains(owner) { continue }
                if let owner, let me, owner == me { continue }   // own note shown in editor
                let tier = (rec["tier"] as? String).flatMap(Tier.init(rawValue:))
                notes.append(CommunityNote(placementRecordName: name,
                                           authorUserID: owner,
                                           text: text,
                                           tier: tier))
            }
            // Deterministic order; newest-first isn't available without a
            // creation-date key, so sort by tier score then text for stability.
            return notes.sorted {
                ($0.tier?.score ?? -1) != ($1.tier?.score ?? -1)
                    ? ($0.tier?.score ?? -1) > ($1.tier?.score ?? -1)
                    : $0.text < $1.text
            }
        } catch {
            return []
        }
    }

    /// Fetch the current user's own note for a restaurant (to prefill the
    /// editor). Single record(for:) by known ID — nil if none / not signed
    /// into iCloud / no placement yet.
    func fetchMyNote(restaurantID: UUID) async -> String? {
        guard isAvailable, let user = await userRecordName() else { return nil }
        let id = placementRecordID(user: user, restaurant: restaurantID)
        guard let rec = try? await publicDB.record(for: id) else { return nil }
        let note = (rec["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// Report an objectionable note. Idempotent per (reporter, placement).
    func reportNote(placementRecordName: String) async -> Bool {
        guard isAvailable, let user = await userRecordName(),
              !placementRecordName.isEmpty else { return false }
        let recID = CKRecord.ID(recordName: "noteReport_\(user)_\(placementRecordName)")
        let rec = CKRecord(recordType: noteReportType, recordID: recID)
        rec["placementName"] = placementRecordName as CKRecordValue
        rec["reporterID"] = user as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.saveNoteReport(placementRecordName: placementRecordName) }
            return true
        } catch {
            return false
        }
    }

    /// Admin: hide one note from everyone (kind="note" exclusion on the owning
    /// placement). The placement's tier keeps counting; only the note text is
    /// suppressed. Reversible via `unhideNote`.
    @discardableResult
    func hideNote(placementRecordName: String) async -> Bool {
        guard isAvailable, await isAdmin(), !placementRecordName.isEmpty else { return false }
        let rec = CKRecord(recordType: exclusionType,
                           recordID: exclusionRecordID(kind: "note", target: placementRecordName))
        rec["kind"] = "note" as CKRecordValue
        rec["target"] = placementRecordName as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            hiddenNoteNames.insert(placementRecordName)
            Task { await FirebaseService.shared.saveExclusion(kind: "note", target: placementRecordName) }
            return true
        } catch { return false }
    }

    /// Admin: fetch reported notes not yet hidden, hydrated with the current
    /// note text (nil if the placement/note was since deleted). Mirrors
    /// `fetchPendingPhotoReports`: page reports, drop any whose note the admin
    /// already hid.
    func fetchPendingNoteReports() async -> [PendingNoteReport] {
        guard isAvailable else { return [] }
        await loadExclusionsIfNeeded()
        var placementNames: [String] = []
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                guard case .success(let rec) = result,
                      let name = rec["placementName"] as? String, !name.isEmpty else { continue }
                placementNames.append(name)
            }
        }
        do {
            let q = CKQuery(recordType: noteReportType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(matching: q, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return []
        }
        // Unique, drop already-hidden, then hydrate note text in parallel.
        let unique = Array(Set(placementNames)).filter { !hiddenNoteNames.contains($0) }
        var out: [PendingNoteReport] = []
        await withTaskGroup(of: PendingNoteReport?.self) { group in
            for name in unique {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    guard let rec = try? await self.publicDB.record(for: CKRecord.ID(recordName: name)),
                          let text = (rec["note"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else { return nil }
                    return PendingNoteReport(
                        placementRecordName: name,
                        authorUserID: self.placementOwnerID(from: name),
                        text: text)
                }
            }
            for await item in group { if let item { out.append(item) } }
        }
        return out
    }

    /// Admin: un-hide a previously hidden note.
    @discardableResult
    func unhideNote(placementRecordName: String) async -> Bool {
        guard isAvailable, await isAdmin() else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [],
                deleting: [exclusionRecordID(kind: "note", target: placementRecordName)],
                savePolicy: .allKeys)
            hiddenNoteNames.remove(placementRecordName)
            Task { await FirebaseService.shared.deleteExclusion(kind: "note", target: placementRecordName) }
            return true
        } catch { return false }
    }

    // MARK: - Dish photos (public DB, CKAsset)

    /// Upload a dish photo (already-compressed JPEG) for a restaurant.
    /// Stamps the photo with the uploader's iCloud user record name so the
    /// app can filter out photos from uploaders the viewer has blocked
    /// (App Review Guideline 1.2).
    func uploadDishPhoto(restaurantID: UUID, jpegData: Data, caption: String?) async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try jpegData.write(to: tmp)
            let record = CKRecord(recordType: photoType)
            record["restaurantID"] = restaurantID.uuidString as CKRecordValue
            record["submitterUserID"] = user as CKRecordValue
            if let caption, !caption.isEmpty {
                record["caption"] = caption as CKRecordValue
            }
            record["image"] = CKAsset(fileURL: tmp)
            _ = try await publicDB.save(record)
            try? FileManager.default.removeItem(at: tmp)
            // Android migration: NOT mirrored to Firestore. The photo is a
            // binary CKAsset; Firestore holds only structured data, so
            // cross-platform photos need Firebase Storage (upload the JPEG,
            // store the download URL in a doc). Tracked as its own task —
            // deferred out of the Phase 2 dual-write, which covers structured
            // surfaces only.
            return true
        } catch {
            return false
        }
    }

    /// Fetch all dish photos for a restaurant, with two layers of filtering
    /// for App Review Guideline 1.2:
    ///   • photos with an admin `PhotoModerated` decision of "hidden" are
    ///     dropped server-side for everyone
    ///   • photos whose `submitterUserID` is in the viewer's local block list
    ///     are dropped client-side
    /// Requires a Queryable index on DishPhoto.restaurantID; returns [] gracefully.
    func fetchDishPhotos(restaurantID: UUID,
                         blockedUploaderIDs: Set<String> = []) async -> [DishPhoto] {
        guard isAvailable else { return [] }
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: photoType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)
            // Batch-check moderation decisions for these specific photos. No
            // schema-level Queryable needed — fetch by recordName.
            let photoIDs = results.map { $0.0.recordName }
            let hidden = await fetchHiddenPhotoIDs(photoIDs: photoIDs)
            var photos: [DishPhoto] = []
            for (_, result) in results {
                guard case .success(let rec) = result,
                      let asset = rec["image"] as? CKAsset,
                      let url = asset.fileURL,
                      let data = try? Data(contentsOf: url) else { continue }
                let photoID = rec.recordID.recordName
                if hidden.contains(photoID) { continue }
                let submitter = rec["submitterUserID"] as? String
                if let submitter, blockedUploaderIDs.contains(submitter) { continue }
                photos.append(DishPhoto(id: photoID,
                                        caption: rec["caption"] as? String,
                                        imageData: data,
                                        submitterUserID: submitter))
            }
            return photos
        } catch {
            return []
        }
    }

    /// Report a dish photo as objectionable. Idempotent per (reporter, photo).
    func reportPhoto(photoID: String) async -> Bool {
        guard isAvailable, let user = await userRecordName(), !photoID.isEmpty else { return false }
        let recID = CKRecord.ID(recordName: "photoReport_\(user)_\(photoID)")
        let rec = CKRecord(recordType: photoReportType, recordID: recID)
        rec["photoID"] = photoID as CKRecordValue
        rec["reporterID"] = user as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.savePhotoReport(photoID: photoID) }
            return true
        } catch {
            return false
        }
    }

    /// Given a set of photo recordNames, return the subset that the admin has
    /// marked "hidden." Uses record(for:) per id so no Queryable index is needed
    /// — fine for the small batch sizes we fetch per restaurant.
    private func fetchHiddenPhotoIDs(photoIDs: [String]) async -> Set<String> {
        guard !photoIDs.isEmpty else { return [] }
        var hidden: Set<String> = []
        await withTaskGroup(of: (String, Bool).self) { group in
            for pid in photoIDs {
                group.addTask { [weak self] in
                    guard let self else { return (pid, false) }
                    let recID = CKRecord.ID(recordName: "photoMod_\(pid)")
                    if let rec = try? await self.publicDB.record(for: recID),
                       (rec["decision"] as? String) == "hidden" {
                        return (pid, true)
                    }
                    return (pid, false)
                }
            }
            for await (pid, isHidden) in group where isHidden { hidden.insert(pid) }
        }
        return hidden
    }

    /// Admin: fetch all photo reports whose photo has NOT yet been moderated
    /// (no PhotoModerated decision on it). Pages the report list, then drops
    /// any whose photo already has a moderator decision.
    func fetchPendingPhotoReports() async -> [PhotoReport] {
        guard isAvailable else { return [] }
        var reports: [PhotoReport] = []
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (id, result) in matches {
                guard case .success(let rec) = result else { continue }
                reports.append(PhotoReport(
                    id: id.recordName,
                    photoID: rec["photoID"] as? String ?? "",
                    reporterID: rec["reporterID"] as? String ?? ""))
            }
        }
        do {
            let q = CKQuery(recordType: photoReportType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(matching: q, resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return []
        }
        // Drop reports whose photo already has a moderator decision (hidden or approved).
        let uniquePhotoIDs = Array(Set(reports.map { $0.photoID }))
        var decided: Set<String> = []
        await withTaskGroup(of: String?.self) { group in
            for pid in uniquePhotoIDs where !pid.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let recID = CKRecord.ID(recordName: "photoMod_\(pid)")
                    return (try? await self.publicDB.record(for: recID)) != nil ? pid : nil
                }
            }
            for await pid in group { if let pid { decided.insert(pid) } }
        }
        return reports.filter { !decided.contains($0.photoID) }
    }

    /// Admin: fetch the underlying DishPhoto for a report — used to render the
    /// admin review queue with the actual image. Returns nil if the photo was
    /// deleted out from under the report.
    func fetchPhoto(photoID: String) async -> DishPhoto? {
        guard isAvailable, !photoID.isEmpty else { return nil }
        do {
            let rec = try await publicDB.record(for: CKRecord.ID(recordName: photoID))
            guard let asset = rec["image"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            return DishPhoto(id: photoID,
                             caption: rec["caption"] as? String,
                             imageData: data,
                             submitterUserID: rec["submitterUserID"] as? String)
        } catch {
            return nil
        }
    }

    /// Admin: hide a photo from everyone (creates an admin-owned PhotoModerated
    /// marker with decision="hidden"). `fetchDishPhotos` filters these out.
    func hidePhoto(photoID: String) async -> Bool {
        await setPhotoDecision(photoID: photoID, decision: "hidden")
    }

    /// Admin: explicitly approve a photo so it drops out of the review queue
    /// without being hidden. Useful for false reports.
    func approvePhoto(photoID: String) async -> Bool {
        await setPhotoDecision(photoID: photoID, decision: "approved")
    }

    private func setPhotoDecision(photoID: String, decision: String) async -> Bool {
        guard isAvailable, !photoID.isEmpty else { return false }
        let recID = CKRecord.ID(recordName: "photoMod_\(photoID)")
        let rec = CKRecord(recordType: photoModType, recordID: recID)
        rec["photoID"] = photoID as CKRecordValue
        rec["decision"] = decision as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.savePhotoModeration(photoID: photoID, decision: decision) }
            return true
        } catch {
            return false
        }
    }

    // MARK: - "Permanently closed" reports

    private func closureRecordID(user: String, restaurant: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "closure_\(user)_\(restaurant.uuidString)")
    }

    func reportClosed(restaurantID: UUID) async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        let record = CKRecord(recordType: closureType,
                              recordID: closureRecordID(user: user, restaurant: restaurantID))
        record["restaurantID"] = restaurantID.uuidString as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.saveClosureReport(restaurantID: restaurantID) }
            return true
        } catch {
            return false
        }
    }

    func unreportClosed(restaurantID: UUID) async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [],
                deleting: [closureRecordID(user: user, restaurant: restaurantID)],
                savePolicy: .allKeys)
            Task { await FirebaseService.shared.deleteClosureReport(restaurantID: restaurantID) }
            return true
        } catch {
            return false
        }
    }

    /// Count of closed-reports for a restaurant + whether the current user is one.
    ///
    /// Ownership check is via recordName prefix, NOT creatorUserRecordID —
    /// Apple's CloudKit returns "__defaultOwner__" from creatorUserRecordID
    /// for records the current user created, so direct comparison against
    /// the user's record name silently fails. The closure recordName is
    /// "closure_<userID>_<restaurantUUID>" (see closureRecordID above), so
    /// we parse ownership from the name. Same pattern as fetchMyPlacements
    /// uses for the placement record type.
    func fetchClosureInfo(restaurantID: UUID) async -> (count: Int, reportedByMe: Bool) {
        guard isAvailable else { return (0, false) }
        let me = await userRecordName()
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: closureType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 200)
            var count = 0
            var mine = false
            let myPrefix = me.map { "closure_\($0)_" }
            for (recordID, result) in results {
                guard case .success = result else { continue }
                count += 1
                if let myPrefix, recordID.recordName.hasPrefix(myPrefix) {
                    mine = true
                }
            }
            return (count, mine)
        } catch {
            return (0, false)
        }
    }

    /// Refresh the per-restaurant closed-report counts cache (pages all reports),
    /// AND the admin-confirmed-closed set. Requires Queryable indexes on
    /// ClosureReport.recordName and ClosureDecision.recordName.
    func refreshClosureCounts() async {
        await refreshAvailability()
        guard isAvailable else { return }

        // 1. Raw report counts (every ClosureReport record).
        var counts: [UUID: Int] = [:]
        func accumulateCounts(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                if case .success(let rec) = result,
                   let s = rec["restaurantID"] as? String,
                   let id = UUID(uuidString: s) {
                    counts[id, default: 0] += 1
                }
            }
        }
        do {
            let query = CKQuery(recordType: closureType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["restaurantID"], resultsLimit: 200)
            accumulateCounts(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["restaurantID"], resultsLimit: 200)
                accumulateCounts(matches)
            }
            closureCounts = counts
        } catch {
            // leave the existing cache as-is on failure
        }

        // 2. Admin-confirmed-closed set (ClosureDecision records with
        //    decision == "closed"). Rejected/open decisions exist as
        //    silent markers — they don't affect display, just remove the
        //    restaurant from the admin pending queue.
        var confirmed: Set<UUID> = []
        func accumulateConfirmed(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                if case .success(let rec) = result,
                   (rec["decision"] as? String) == "closed",
                   let s = rec["restaurantID"] as? String,
                   let id = UUID(uuidString: s) {
                    confirmed.insert(id)
                }
            }
        }
        do {
            let query = CKQuery(recordType: closureDecisionType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["restaurantID", "decision"], resultsLimit: 200)
            accumulateConfirmed(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["restaurantID", "decision"], resultsLimit: 200)
                accumulateConfirmed(matches)
            }
            confirmedClosedIDs = confirmed
        } catch {
            // leave the existing set as-is on failure
        }
    }

    // MARK: - Closure decisions (v1.3.1 — admin moderation)

    private func closureDecisionRecordID(restaurant: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "closureDecision_\(restaurant.uuidString)")
    }

    /// Admin: confirm a restaurant is permanently closed. Adds the
    /// restaurant to confirmedClosedIDs and triggers strikethrough +
    /// closure banner everywhere in the app.
    func confirmClosed(restaurantID: UUID) async -> Bool {
        await setClosureDecision(restaurantID: restaurantID, decision: "closed")
    }

    /// Admin: explicitly mark a restaurant as still open (false-report
    /// rejection). Doesn't delete user reports — just stamps an admin
    /// "open" marker so the restaurant drops out of the pending-review
    /// queue without surfacing as closed to users.
    func markOpen(restaurantID: UUID) async -> Bool {
        await setClosureDecision(restaurantID: restaurantID, decision: "open")
    }

    /// Admin: revert a previous closure decision (rare — used if admin
    /// confirmed-closed by mistake and wants to unsay it).
    func clearClosureDecision(restaurantID: UUID) async -> Bool {
        guard isAvailable else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [],
                deleting: [closureDecisionRecordID(restaurant: restaurantID)],
                savePolicy: .allKeys)
            Task { await FirebaseService.shared.deleteClosureDecision(restaurantID: restaurantID) }
            return true
        } catch {
            return false
        }
    }

    private func setClosureDecision(restaurantID: UUID, decision: String) async -> Bool {
        guard isAvailable else { return false }
        let recID = closureDecisionRecordID(restaurant: restaurantID)
        let rec = CKRecord(recordType: closureDecisionType, recordID: recID)
        rec["restaurantID"] = restaurantID.uuidString as CKRecordValue
        rec["decision"] = decision as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.saveClosureDecision(restaurantID: restaurantID, decision: decision) }
            return true
        } catch {
            return false
        }
    }

    /// Admin: pending closure reports — restaurants with ≥1 ClosureReport
    /// records that DO NOT yet have a ClosureDecision (either "closed" or
    /// "open"). Returns array of (restaurantID, reportCount) sorted by
    /// count desc so the admin can triage by signal strength.
    func fetchPendingClosureReports() async -> [(restaurantID: UUID, count: Int)] {
        await refreshClosureCounts()   // make sure counts + decisions are current
        guard isAvailable else { return [] }

        // Set of restaurants that already have ANY decision (closed or open).
        // We want the admin queue to drop both — closed ones are already
        // handled, open ones were already rejected.
        var decided: Set<UUID> = []
        do {
            let q = CKQuery(recordType: closureDecisionType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: q, desiredKeys: ["restaurantID"], resultsLimit: 200)
            func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
                for (_, result) in matches {
                    if case .success(let rec) = result,
                       let s = rec["restaurantID"] as? String,
                       let id = UUID(uuidString: s) {
                        decided.insert(id)
                    }
                }
            }
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["restaurantID"], resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            // If the decision fetch fails, fall back to "everything is pending"
        }

        return closureCounts
            .filter { !decided.contains($0.key) && $0.value > 0 }
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Foodie Pro profiles

    func currentUserID() async -> String? {
        await userRecordName()
    }

    private func profileRecordID(user: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile_\(user)")
    }

    /// The current user's (displayName, status, isAppleVerified).
    /// status is ""/"requested"/"approved".
    /// v1.7 Feature B+: returns the SIWA-verified flag too so the UI can
    /// reflect it without a second round-trip.
    func fetchMyProfile() async -> (displayName: String, status: String, isAppleVerified: Bool) {
        guard isAvailable, let user = await userRecordName() else { return ("", "", false) }
        return await fetchProfile(forUserID: user)
    }

    /// v1.7 (Feature C+B+): fetch any user's profile by their userRecordName,
    /// including the Apple-verified flag. Used by the friend-tier-link
    /// flow (FriendTierView shows a checkmark next to a verified friend's
    /// name).
    func fetchProfile(forUserID user: String) async -> (displayName: String, status: String, isAppleVerified: Bool) {
        guard isAvailable, !user.isEmpty else { return ("", "", false) }
        do {
            let rec = try await publicDB.record(for: profileRecordID(user: user))
            let verified = (rec["isAppleVerified"] as? Int64) == 1
            return (rec["displayName"] as? String ?? "", rec["status"] as? String ?? "", verified)
        } catch {
            return ("", "", false)
        }
    }

    /// Upsert the user's profile. Sets displayName; if requestingPro and not
    /// already approved, marks status "requested". Never downgrades an approved pro.
    /// v1.7 Feature B+: also persists `isAppleVerified` so the Community /
    /// Pros leaderboard can show a verified-name badge next to SIWA-signed-
    /// in users. Apple's name is non-fungible (one app + Apple ID = one
    /// stable identifier), so the badge is meaningful — it signals "this
    /// person verified their identity through Apple."
    /// CloudKit schema NOTE: this field auto-creates in the Development
    /// environment on first write but MUST be pre-declared in Production
    /// before TestFlight / App Store builds will see it. Add Int64-typed
    /// field `isAppleVerified` to the FoodieProfile record type in CK
    /// Dashboard → Dev → Deploy Schema Changes → Production.
    func saveProfile(displayName: String, requestingPro: Bool, isAppleVerified: Bool = false) async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        let id = profileRecordID(user: user)
        let record: CKRecord
        var status = ""
        if let existing = try? await publicDB.record(for: id) {
            record = existing
            status = existing["status"] as? String ?? ""
        } else {
            record = CKRecord(recordType: profileType, recordID: id)
        }
        record["displayName"] = displayName as CKRecordValue
        record["userID"] = user as CKRecordValue
        if requestingPro && status != "approved" { status = "requested" }
        record["status"] = status as CKRecordValue
        // Stored as Int64 (0/1) because CKRecord doesn't natively support
        // Bool — the typical CloudKit convention.
        record["isAppleVerified"] = (isAppleVerified ? 1 : 0) as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            let mirroredStatus = status
            Task { await FirebaseService.shared.saveProfile(displayName: displayName, status: mirroredStatus) }
            return true
        } catch {
            return false
        }
    }

    /// v1.7 Feature B+: fetch the set of userRecordNames currently marked
    /// `isAppleVerified=true` in their FoodieProfile. Used by the Pros /
    /// Community leaderboard to overlay an Apple-verified checkmark next
    /// to each verified Pro's name.
    /// Implementation: pages FoodieProfile records and filters client-side.
    /// At early-app scale (sub-thousand profiles) the overhead is fine.
    func fetchAppleVerifiedUserIDs() async -> Set<String> {
        guard isAvailable else { return [] }
        var out: Set<String> = []
        let query = CKQuery(recordType: profileType, predicate: NSPredicate(value: true))
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                guard case .success(let rec) = result,
                      let userID = rec["userID"] as? String,
                      let verified = rec["isAppleVerified"] as? Int64,
                      verified == 1 else { continue }
                out.insert(userID)
            }
        }
        do {
            var (matches, cursor) = try await publicDB.records(
                matching: query,
                desiredKeys: ["userID", "isAppleVerified"],
                resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            // Schema not yet deployed to Prod, or transient — return what
            // we have. UI degrades to "no badges shown" gracefully.
        }
        return out
    }

    /// Whether a specific user is an approved Foodie Pro. Checks their admin-owned
    /// ProApproval record directly via record(for:) — needs no index, and avoids
    /// the creatorUserRecordID "__defaultOwner__" quirk for a user's own records.
    private func isApproved(userID: String) async -> Bool {
        guard !userID.isEmpty else { return false }
        return (try? await publicDB.record(for: CKRecord.ID(recordName: "approval_\(userID)"))) != nil
    }

    /// v1.7: admin-only stats. Distinct counts across CloudKit. Pages
    /// through Placement records once and tallies; pages FoodieProfile
    /// for the profile count. Single round-trip per record type, no
    /// extra indexes needed. Returns zeroed stats on any error path —
    /// caller's UI degrades to "no stats" rather than crashing.
    struct AdminStats {
        var activeUsers: Int        // distinct user IDs with at least one placement
        var totalPlacements: Int
        var restaurantsRanked: Int  // distinct restaurant IDs appearing in any placement
        var profileCount: Int       // total FoodieProfile records
        /// v1.7: how many users are at each FoodieRank tier. Derived from
        /// the placements-per-user tally that fetchAdminStats already
        /// builds. Rank cutoffs come from FoodieRank.from(placementCount:).
        var usersByRank: [FoodieRank: Int]
    }

    func fetchAdminStats() async -> AdminStats {
        guard isAvailable else {
            return AdminStats(activeUsers: 0, totalPlacements: 0,
                              restaurantsRanked: 0, profileCount: 0,
                              usersByRank: [:])
        }
        var placementsPerUser: [String: Int] = [:]
        var restaurants: Set<String> = []
        var placementCount = 0

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, _) in matches {
                placementCount += 1
                if let owner = placementOwnerID(from: recordID.recordName) {
                    placementsPerUser[owner, default: 0] += 1
                }
                // Recover the restaurant UUID from the trailing 36 chars
                // of the recordName ("placement_<user>_<restaurantUUID>").
                let name = recordID.recordName
                if name.count >= 36 {
                    let uuid = String(name.suffix(36))
                    if UUID(uuidString: uuid) != nil {
                        restaurants.insert(uuid)
                    }
                }
            }
        }

        do {
            let placementQuery = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: placementQuery,
                desiredKeys: [],
                resultsLimit: 400)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, resultsLimit: 400)
                accumulate(matches)
            }
        } catch {
            // Partial result is fine — return what we tallied so far.
        }

        // FoodieProfile doesn't have a recordName Queryable index, so
        // TRUEPREDICATE queries against it fail silently. Instead we
        // OR the three known `status` values ("", "requested",
        // "approved") — status IS a Queryable index on FoodieProfile,
        // and every profile is written with one of those values by
        // saveProfile. Union the results per status.
        var profileCount = 0
        for statusValue in ["", "requested", "approved"] {
            do {
                let profileQuery = CKQuery(
                    recordType: profileType,
                    predicate: NSPredicate(format: "status == %@", statusValue))
                var (matches, cursor) = try await publicDB.records(
                    matching: profileQuery,
                    desiredKeys: [],
                    resultsLimit: 400)
                profileCount += matches.count
                while let c = cursor {
                    (matches, cursor) = try await publicDB.records(
                        continuingMatchFrom: c, resultsLimit: 400)
                    profileCount += matches.count
                }
            } catch {
                // Partial-count is acceptable — skip this bucket, keep
                // whatever the other queries gave us.
            }
        }

        // v1.7: derive rank distribution from the placements-per-user
        // tally. Skips Newcomer for anyone with 0 placements (they're
        // not in placementsPerUser at all — no floor pollution).
        var usersByRank: [FoodieRank: Int] = [:]
        for (_, count) in placementsPerUser {
            if let rank = FoodieRank.from(placementCount: count) {
                usersByRank[rank, default: 0] += 1
            }
        }

        return AdminStats(
            activeUsers: placementsPerUser.count,
            totalPlacements: placementCount,
            restaurantsRanked: restaurants.count,
            profileCount: profileCount,
            usersByRank: usersByRank
        )
    }

    /// Extract the owner's userID from a placement recordName,
    /// which is "placement_<userID>_<restaurantUUID>".
    private func placementOwnerID(from recordName: String) -> String? {
        let prefix = "placement_"
        guard recordName.hasPrefix(prefix) else { return nil }
        let body = recordName.dropFirst(prefix.count)   // "<userID>_<restaurantUUID>"
        guard body.count > 37 else { return nil }        // 36-char UUID + "_" separator
        let userID = String(body.dropLast(37))
        return userID.isEmpty ? nil : userID
    }

    /// Community consensus computed ONLY from approved Foodie Pros' placements.
    /// Owner is parsed from each placement's recordName (robust), then each unique
    /// owner's approval is checked directly — no extra index, no creator-field quirk.
    func fetchProCommunityTiers() async -> [UUID: CommunityTier] {
        guard isAvailable else { return [:] }

        await loadExclusionsIfNeeded()
        // 1. Pull all placements (Placement.recordName index is already deployed).
        var placements: [(owner: String, restaurant: UUID, score: Int)] = []
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                guard case .success(let rec) = result,
                      let owner = placementOwnerID(from: recordID.recordName),
                      let s = rec["restaurantID"] as? String, let rid = UUID(uuidString: s),
                      let score = rec["score"] as? Int,
                      // v1.8: skip admin-excluded ratings / banned users.
                      !isExcluded(recordName: recordID.recordName, owner: owner)
                else { continue }
                placements.append((owner, rid, score))
            }
        }
        do {
            let query = CKQuery(recordType: placementType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["restaurantID", "score"], resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["restaurantID", "score"], resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return [:]
        }

        // 2. Which unique owners are approved pros (one record(for:) each — no index).
        var pros: Set<String> = []
        for owner in Set(placements.map { $0.owner }) {
            if await isApproved(userID: owner) { pros.insert(owner) }
        }
        guard !pros.isEmpty else { return [:] }

        // 3. Aggregate only the pros' placements.
        var sums: [UUID: (total: Int, count: Int)] = [:]
        for placement in placements where pros.contains(placement.owner) {
            var entry = sums[placement.restaurant] ?? (0, 0)
            entry.total += placement.score
            entry.count += 1
            sums[placement.restaurant] = entry
        }

        var out: [UUID: CommunityTier] = [:]
        for (rid, agg) in sums where agg.count > 0 {
            let avg = Double(agg.total) / Double(agg.count)
            out[rid] = CommunityTier(tier: .from(averageScore: avg), count: agg.count, average: avg)
        }
        return out
    }

    // MARK: - Admin (Foodie Pro approval)

    func isAdmin() async -> Bool {
        guard let uid = await userRecordName() else { return false }
        return adminUserIDs.contains(uid)
    }

    /// Whether the current user has been approved (has a ProApproval record).
    func amIApproved() async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        return (try? await publicDB.record(for: CKRecord.ID(recordName: "approval_\(user)"))) != nil
    }

    /// Admin: everyone who requested, split into pending vs. already-approved.
    /// v1.7 Feature B+: ProRequest now includes the Apple-verified flag
    /// read from `isAppleVerified` on the FoodieProfile (Int64 0/1 because
    /// CKRecord doesn't natively store Bool). Missing field = not verified.
    func fetchProRequests() async -> (pending: [ProRequest], approved: [ProRequest]) {
        guard isAvailable else { return ([], []) }
        let query = CKQuery(recordType: profileType, predicate: NSPredicate(format: "status == %@", "requested"))
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 200)
            var pending: [ProRequest] = []
            var approved: [ProRequest] = []
            for (id, result) in results {
                guard case .success(let rec) = result else { continue }
                let uid = rec["userID"] as? String ?? ""
                let verified = (rec["isAppleVerified"] as? Int64) == 1
                let req = ProRequest(id: id.recordName,
                                     displayName: rec["displayName"] as? String ?? "",
                                     userID: uid,
                                     isAppleVerified: verified)
                if await isApproved(userID: uid) { approved.append(req) } else { pending.append(req) }
            }
            return (pending, approved)
        } catch {
            return ([], [])
        }
    }

    /// Admin: approve a user — creates an admin-owned ProApproval record.
    func approvePro(userID: String) async -> Bool {
        guard isAvailable, !userID.isEmpty else { return false }
        let rec = CKRecord(recordType: approvalType,
                           recordID: CKRecord.ID(recordName: "approval_\(userID)"))
        rec["userID"] = userID as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            Task { await FirebaseService.shared.saveProApproval(forUserID: userID) }
            return true
        } catch {
            return false
        }
    }

    /// Admin: revoke — deletes the ProApproval record.
    func revokePro(userID: String) async -> Bool {
        guard isAvailable, !userID.isEmpty else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: "approval_\(userID)")], savePolicy: .allKeys)
            Task { await FirebaseService.shared.deleteProApproval(forUserID: userID) }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Restaurant suggestions ("crowd add a missing spot")

    /// Submit a missing-restaurant suggestion (creates a user-owned record).
    func submitSuggestion(name: String, address: String, area: String,
                          cuisines: [String], description: String) async -> Bool {
        guard isAvailable, let user = await userRecordName() else { return false }
        let rec = CKRecord(recordType: suggestionType)
        rec["name"] = name as CKRecordValue
        rec["address"] = address as CKRecordValue
        rec["area"] = area as CKRecordValue
        rec["cuisines"] = cuisines as CKRecordValue
        rec["description"] = description as CKRecordValue
        rec["submitterUserID"] = user as CKRecordValue
        do {
            _ = try await publicDB.save(rec)
            Task { _ = await FirebaseService.shared.saveSuggestion(name: name, address: address, area: area, cuisines: cuisines, description: description) }
            return true
        }
        catch { return false }
    }

    /// Admin: suggestions that are neither approved (have a LiveRestaurant) nor dismissed.
    func fetchPendingSuggestions() async -> [Suggestion] {
        guard isAvailable else { return [] }

        // Collect suggestion ids that are RESOLVED — either approved (LiveRestaurant
        // references them) or dismissed (SuggestionDismissed records).
        var resolved: Set<String> = []
        func accSID(_ m: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, r) in m {
                if case .success(let rec) = r, let sid = rec["suggestionID"] as? String {
                    resolved.insert(sid)
                }
            }
        }
        for type in [liveType, dismissalType] {
            do {
                let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
                var (m, c) = try await publicDB.records(matching: q, desiredKeys: ["suggestionID"], resultsLimit: 200)
                accSID(m)
                while let cur = c {
                    (m, c) = try await publicDB.records(continuingMatchFrom: cur, desiredKeys: ["suggestionID"], resultsLimit: 200)
                    accSID(m)
                }
            } catch { /* on error, treat as unresolved */ }
        }

        // Fetch all suggestions, drop the ones already resolved.
        var out: [Suggestion] = []
        func accSugg(_ m: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (id, r) in m {
                guard case .success(let rec) = r, !resolved.contains(id.recordName) else { continue }
                out.append(Suggestion(
                    id: id.recordName,
                    name: rec["name"] as? String ?? "",
                    address: rec["address"] as? String ?? "",
                    area: rec["area"] as? String ?? "",
                    cuisines: rec["cuisines"] as? [String] ?? [],
                    description: rec["description"] as? String ?? "",
                    submitterUserID: rec["submitterUserID"] as? String ?? ""
                ))
            }
        }
        do {
            let q = CKQuery(recordType: suggestionType, predicate: NSPredicate(value: true))
            var (m, c) = try await publicDB.records(matching: q, resultsLimit: 200)
            accSugg(m)
            while let cur = c {
                (m, c) = try await publicDB.records(continuingMatchFrom: cur, resultsLimit: 200)
                accSugg(m)
            }
        } catch { return [] }
        return out
    }

    /// Admin: approve a suggestion — creates an admin-owned LiveRestaurant record
    /// with the suggestion's data + geocoded coords. The app fetches LiveRestaurants
    /// at launch and merges them into the live restaurant list.
    func approveSuggestion(_ s: Suggestion, latitude: Double, longitude: Double) async -> Bool {
        guard isAvailable else { return false }
        let restaurantUUID = UUID()
        let restaurantID = restaurantUUID.uuidString
        let recID = CKRecord.ID(recordName: "live_\(restaurantID)")
        let rec = CKRecord(recordType: liveType, recordID: recID)
        rec["restaurantID"] = restaurantID as CKRecordValue
        rec["name"] = s.name as CKRecordValue
        rec["latitude"] = latitude as CKRecordValue
        rec["longitude"] = longitude as CKRecordValue
        rec["area"] = s.area as CKRecordValue
        rec["address"] = s.address as CKRecordValue
        rec["cuisines"] = (s.cuisines.isEmpty ? ["other"] : s.cuisines) as CKRecordValue
        rec["priceTier"] = "$$" as CKRecordValue
        rec["isFastFood"] = 0 as CKRecordValue
        rec["description"] = (s.description.isEmpty ? "Suggested by the community." : s.description) as CKRecordValue
        rec["signatureDishes"] = ([] as [String]) as CKRecordValue
        rec["suggestionID"] = s.id as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            let cuisines = s.cuisines.isEmpty ? ["other"] : s.cuisines
            let desc = s.description.isEmpty ? "Suggested by the community." : s.description
            Task {
                await FirebaseService.shared.saveLiveRestaurant(
                    restaurantID: restaurantUUID, suggestionID: s.id, name: s.name,
                    latitude: latitude, longitude: longitude, area: s.area, address: s.address,
                    cuisines: cuisines, priceTier: "$$", isFastFood: false, description: desc)
            }
            return true
        } catch {
            return false
        }
    }

    /// Admin: reject a suggestion — creates an admin-owned SuggestionDismissed marker
    /// so the suggestion drops out of the pending queue.
    ///
    /// Android migration: NOT mirrored. The Firestore suggestion doc uses an
    /// auto-generated ID (see FirebaseService.saveSuggestion), which does not
    /// equal `s.id` (a CloudKit recordName), so we can't reliably target it to
    /// flip its status. Suggestion approve/reject reconciliation is a Phase 3
    /// (backfill) concern; the admin queue is still read from CloudKit.
    func rejectSuggestion(_ s: Suggestion) async -> Bool {
        guard isAvailable else { return false }
        let recID = CKRecord.ID(recordName: "reject_\(s.id)")
        let rec = CKRecord(recordType: dismissalType, recordID: recID)
        rec["suggestionID"] = s.id as CKRecordValue
        do {
            _ = try await publicDB.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            return false
        }
    }

    /// Fetch all LiveRestaurant records and decode them as Restaurants for the
    /// store to merge with the bundled seed. Requires recordName Queryable on LiveRestaurant.
    func fetchLiveRestaurants() async -> [Restaurant] {
        guard isAvailable else { return [] }
        var out: [Restaurant] = []
        do {
            let q = CKQuery(recordType: liveType, predicate: NSPredicate(value: true))
            var (m, c) = try await publicDB.records(matching: q, resultsLimit: 200)
            for (_, r) in m { if let resto = liveToRestaurant(r) { out.append(resto) } }
            while let cur = c {
                (m, c) = try await publicDB.records(continuingMatchFrom: cur, resultsLimit: 200)
                for (_, r) in m { if let resto = liveToRestaurant(r) { out.append(resto) } }
            }
        } catch {
            return []
        }
        return out
    }

    private func liveToRestaurant(_ result: Result<CKRecord, Error>) -> Restaurant? {
        guard case .success(let rec) = result,
              let ridStr = rec["restaurantID"] as? String, let rid = UUID(uuidString: ridStr),
              let name = rec["name"] as? String,
              let lat = rec["latitude"] as? Double,
              let lon = rec["longitude"] as? Double,
              let areaStr = rec["area"] as? String, let area = Area(rawValue: areaStr),
              let address = rec["address"] as? String,
              let cuisineStrs = rec["cuisines"] as? [String],
              let priceStr = rec["priceTier"] as? String, let price = PriceTier(rawValue: priceStr),
              let desc = rec["description"] as? String
        else { return nil }
        let cuisines = cuisineStrs.compactMap { Cuisine(rawValue: $0) }
        let ffInt = (rec["isFastFood"] as? Int) ?? 0
        return Restaurant(
            id: rid, name: name, latitude: lat, longitude: lon, area: area,
            address: address, cuisines: cuisines.isEmpty ? [.other] : cuisines, priceTier: price,
            isFastFood: ffInt != 0,
            website: rec["website"] as? String,
            phone: rec["phone"] as? String,
            description: desc,
            signatureDishes: rec["signatureDishes"] as? [String] ?? []
        )
    }
}
