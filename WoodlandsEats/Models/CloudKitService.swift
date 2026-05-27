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
struct DishPhoto: Identifiable {
    let id: String
    let caption: String?
    let imageData: Data
}

/// A user's Foodie Pro request (their FoodieProfile), for the admin approval UI.
struct ProRequest: Identifiable {
    let id: String          // FoodieProfile recordName
    let displayName: String
    let userID: String
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
    /// iCloud user record names allowed to approve Foodie Pros (shown on the Profile tab).
    private let adminUserIDs: Set<String> = ["_e8b0bfe996b6e232421afa393ab8a3b"]

    /// Per-restaurant count of "permanently closed" reports; refreshed on launch
    /// and after a report toggle. Read by the list + map to flag closed spots.
    private(set) var closureCounts: [UUID: Int] = [:]

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
    func savePlacement(restaurantID: UUID, tier: Tier) async {
        guard isAvailable, let user = await userRecordName() else { return }
        let record = CKRecord(recordType: placementType,
                              recordID: placementRecordID(user: user, restaurant: restaurantID))
        record["restaurantID"] = restaurantID.uuidString as CKRecordValue
        record["tier"] = tier.rawValue as CKRecordValue
        record["score"] = tier.score as CKRecordValue
        _ = try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    func removePlacement(restaurantID: UUID) async {
        guard isAvailable, let user = await userRecordName() else { return }
        _ = try? await publicDB.modifyRecords(
            saving: [],
            deleting: [placementRecordID(user: user, restaurant: restaurantID)],
            savePolicy: .allKeys)
    }

    /// Average everyone's placements for a restaurant into a consensus tier.
    /// Returns nil if no one has ranked it yet (or CloudKit is unavailable).
    func fetchCommunityTier(restaurantID: UUID) async -> CommunityTier? {
        guard isAvailable else { return nil }
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: placementType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 500)
            let scores: [Int] = results.compactMap { _, result in
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
        var sums: [UUID: (total: Int, count: Int)] = [:]
        let keys = ["restaurantID", "score"]

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                guard case .success(let rec) = result,
                      let ridStr = rec["restaurantID"] as? String,
                      let rid = UUID(uuidString: ridStr),
                      let score = rec["score"] as? Int else { continue }
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

    // MARK: - Dish photos (public DB, CKAsset)

    /// Upload a dish photo (already-compressed JPEG) for a restaurant.
    func uploadDishPhoto(restaurantID: UUID, jpegData: Data, caption: String?) async -> Bool {
        guard isAvailable else { return false }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try jpegData.write(to: tmp)
            let record = CKRecord(recordType: "DishPhoto")
            record["restaurantID"] = restaurantID.uuidString as CKRecordValue
            if let caption, !caption.isEmpty {
                record["caption"] = caption as CKRecordValue
            }
            record["image"] = CKAsset(fileURL: tmp)
            _ = try await publicDB.save(record)
            try? FileManager.default.removeItem(at: tmp)
            return true
        } catch {
            return false
        }
    }

    /// Fetch all dish photos for a restaurant (requires a Queryable index on
    /// DishPhoto.restaurantID; returns [] gracefully until that exists).
    func fetchDishPhotos(restaurantID: UUID) async -> [DishPhoto] {
        guard isAvailable else { return [] }
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: "DishPhoto", predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)
            var photos: [DishPhoto] = []
            for (_, result) in results {
                guard case .success(let rec) = result,
                      let asset = rec["image"] as? CKAsset,
                      let url = asset.fileURL,
                      let data = try? Data(contentsOf: url) else { continue }
                photos.append(DishPhoto(id: rec.recordID.recordName,
                                        caption: rec["caption"] as? String,
                                        imageData: data))
            }
            return photos
        } catch {
            return []
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
            return true
        } catch {
            return false
        }
    }

    /// Count of closed-reports for a restaurant + whether the current user is one.
    func fetchClosureInfo(restaurantID: UUID) async -> (count: Int, reportedByMe: Bool) {
        guard isAvailable else { return (0, false) }
        let me = await userRecordName()
        let predicate = NSPredicate(format: "restaurantID == %@", restaurantID.uuidString)
        let query = CKQuery(recordType: closureType, predicate: predicate)
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 200)
            var count = 0
            var mine = false
            for (_, result) in results {
                guard case .success(let rec) = result else { continue }
                count += 1
                if let me, rec.creatorUserRecordID?.recordName == me { mine = true }
            }
            return (count, mine)
        } catch {
            return (0, false)
        }
    }

    /// Refresh the per-restaurant closed-report counts cache (pages all reports).
    /// Requires a Queryable index on ClosureReport.recordName.
    func refreshClosureCounts() async {
        await refreshAvailability()
        guard isAvailable else { return }
        var counts: [UUID: Int] = [:]

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
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
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["restaurantID"], resultsLimit: 200)
                accumulate(matches)
            }
            closureCounts = counts
        } catch {
            // leave the existing cache as-is on failure
        }
    }

    // MARK: - Foodie Pro profiles

    func currentUserID() async -> String? {
        await userRecordName()
    }

    private func profileRecordID(user: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile_\(user)")
    }

    /// The current user's (displayName, status); status is ""/"requested"/"approved".
    func fetchMyProfile() async -> (displayName: String, status: String) {
        guard isAvailable, let user = await userRecordName() else { return ("", "") }
        do {
            let rec = try await publicDB.record(for: profileRecordID(user: user))
            return (rec["displayName"] as? String ?? "", rec["status"] as? String ?? "")
        } catch {
            return ("", "")   // no profile yet
        }
    }

    /// Upsert the user's profile. Sets displayName; if requestingPro and not
    /// already approved, marks status "requested". Never downgrades an approved pro.
    func saveProfile(displayName: String, requestingPro: Bool) async -> Bool {
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
        do {
            _ = try await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            return false
        }
    }

    /// userIDs of all approved Foodie Pros. Approvals are admin-owned `ProApproval`
    /// records (a user can't write another user's FoodieProfile, so approval is a
    /// separate record the admin creates). Requires recordName Queryable on ProApproval.
    private func fetchApprovedProIDs() async -> Set<String> {
        guard isAvailable else { return [] }
        var ids: Set<String> = []
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                if case .success(let rec) = result, let uid = rec["userID"] as? String {
                    ids.insert(uid)
                }
            }
        }
        do {
            let query = CKQuery(recordType: approvalType, predicate: NSPredicate(value: true))
            var (matches, cursor) = try await publicDB.records(
                matching: query, desiredKeys: ["userID"], resultsLimit: 200)
            accumulate(matches)
            while let c = cursor {
                (matches, cursor) = try await publicDB.records(
                    continuingMatchFrom: c, desiredKeys: ["userID"], resultsLimit: 200)
                accumulate(matches)
            }
        } catch {
            return []
        }
        return ids
    }

    /// Community consensus computed ONLY from approved Foodie Pros' placements.
    func fetchProCommunityTiers() async -> [UUID: CommunityTier] {
        guard isAvailable else { return [:] }
        let pros = await fetchApprovedProIDs()
        guard !pros.isEmpty else { return [:] }
        var sums: [UUID: (total: Int, count: Int)] = [:]

        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, result) in matches {
                guard case .success(let rec) = result,
                      let creator = rec.creatorUserRecordID?.recordName, pros.contains(creator),
                      let s = rec["restaurantID"] as? String, let rid = UUID(uuidString: s),
                      let score = rec["score"] as? Int else { continue }
                var entry = sums[rid] ?? (0, 0)
                entry.total += score
                entry.count += 1
                sums[rid] = entry
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
    func fetchProRequests() async -> (pending: [ProRequest], approved: [ProRequest]) {
        guard isAvailable else { return ([], []) }
        let approvedIDs = await fetchApprovedProIDs()
        let query = CKQuery(recordType: profileType, predicate: NSPredicate(format: "status == %@", "requested"))
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 200)
            var pending: [ProRequest] = []
            var approved: [ProRequest] = []
            for (id, result) in results {
                guard case .success(let rec) = result else { continue }
                let uid = rec["userID"] as? String ?? ""
                let req = ProRequest(id: id.recordName,
                                     displayName: rec["displayName"] as? String ?? "",
                                     userID: uid)
                if approvedIDs.contains(uid) { approved.append(req) } else { pending.append(req) }
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
            return true
        } catch {
            return false
        }
    }
}
