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
}
