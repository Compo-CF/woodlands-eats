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

/// A user-submitted report flagging a dish photo as objectionable
/// (admin moderation queue, App Review Guideline 1.2).
struct PhotoReport: Identifiable {
    let id: String          // PhotoReport recordName
    let photoID: String     // DishPhoto recordName
    let reporterID: String
}

/// A user's Foodie Pro request (their FoodieProfile), for the admin approval UI.
struct ProRequest: Identifiable {
    let id: String          // FoodieProfile recordName
    let displayName: String
    let userID: String
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
    /// v1.3: per-user "I've been here" list. Single record per user with
    /// the whole restaurant-id set as an array — chosen over per-restaurant
    /// records because the data is purely personal (no community
    /// aggregation), small (a few hundred UUIDs max), and last-write-wins
    /// is fine for the rare cross-device conflict.
    private let visitedType = "VisitedList"
    /// Admin-owned per-photo decision marker. recordName: `photoMod_<photoID>`.
    /// Field `decision` is "hidden" or "approved" — hidden photos are filtered
    /// out of `fetchDishPhotos` for everyone; approved photos drop out of the
    /// admin queue but stay visible.
    private let photoModType = "PhotoModerated"
    /// iCloud user record names allowed to approve Foodie Pros (shown on the Profile tab).
    private let adminUserIDs: Set<String> = ["_e8b0bfe996b6e232421afac393ab8a3b"]

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

    /// Whether a specific user is an approved Foodie Pro. Checks their admin-owned
    /// ProApproval record directly via record(for:) — needs no index, and avoids
    /// the creatorUserRecordID "__defaultOwner__" quirk for a user's own records.
    private func isApproved(userID: String) async -> Bool {
        guard !userID.isEmpty else { return false }
        return (try? await publicDB.record(for: CKRecord.ID(recordName: "approval_\(userID)"))) != nil
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

        // 1. Pull all placements (Placement.recordName index is already deployed).
        var placements: [(owner: String, restaurant: UUID, score: Int)] = []
        func accumulate(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matches {
                guard case .success(let rec) = result,
                      let owner = placementOwnerID(from: recordID.recordName),
                      let s = rec["restaurantID"] as? String, let rid = UUID(uuidString: s),
                      let score = rec["score"] as? Int else { continue }
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
                let req = ProRequest(id: id.recordName,
                                     displayName: rec["displayName"] as? String ?? "",
                                     userID: uid)
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
        do { _ = try await publicDB.save(rec); return true }
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
        let restaurantID = UUID().uuidString
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
            return true
        } catch {
            return false
        }
    }

    /// Admin: reject a suggestion — creates an admin-owned SuggestionDismissed marker
    /// so the suggestion drops out of the pending queue.
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
