import Foundation
import FirebaseAuth
import FirebaseFirestore
import Observation

/// v1.6 (Android migration A2): the cross-platform data layer.
/// Mirrors CloudKitService's write surface — every save/delete in
/// CloudKitService has a parallel here, called as a fire-and-forget
/// Task alongside the CloudKit call. Reads still come from CloudKit
/// through v1.7; Firestore reads turn on in v1.7's cutover.
///
/// Identity model (Phase 3 — full-backfill decision):
///   - Anonymous Firebase Auth provides the AUTH session (request.auth.uid),
///     satisfying "must be signed in" security rules. Each install gets a
///     unique Firebase UID.
///   - The CANONICAL Firestore user key is the iCloud user record name
///     (`linkedUserID`), set by CloudKitService once it resolves the signed-in
///     iCloud account. This makes live dual-writes key by the SAME id the full
///     CloudKit→Firestore backfill uses, so the same person never double-counts
///     under two ids.
///   - When there's no iCloud account (simulator, or a future Android user),
///     `effectiveUserID` falls back to the Firebase anon UID. Apple users who
///     switch to Android start fresh — an accepted tradeoff (they rarely do).
///
/// Schema reference: docs/firestore-schema.md
/// Security rules: docs/firestore.rules
///
/// Every write here is fire-and-forget. Failures log to the console
/// but don't propagate to the UI — CloudKit is still authoritative
/// through the read-cutover.
@Observable
final class FirebaseService {
    /// Lazy singleton so it's created (and touches the Firebase SDK) only
    /// AFTER FirebaseApp.configure() runs at app launch, and so CloudKitService
    /// can route dual-writes through it without environment plumbing.
    static let shared = FirebaseService()

    private(set) var isReady = false
    /// The Firebase anonymous auth UID (the AUTH identity / request.auth.uid).
    private(set) var userID: String?

    /// The signed-in iCloud user record name, once CloudKitService resolves it.
    /// This is the CANONICAL Firestore document key (see the identity model
    /// above). @ObservationIgnored — nothing observes it.
    @ObservationIgnored private var linkedUserID: String?

    /// The id every user-scoped Firestore doc is keyed by: the iCloud user
    /// record name when available, else the Firebase anon UID.
    var effectiveUserID: String? { linkedUserID ?? userID }

    /// Called by CloudKitService once the signed-in iCloud user record name is
    /// known, so live dual-writes align with the full backfill's keying. No-op
    /// when there's no iCloud account (falls back to the Firebase anon UID).
    func linkUser(_ cloudKitUserID: String?) {
        guard let cloudKitUserID, !cloudKitUserID.isEmpty else { return }
        linkedUserID = cloudKitUserID
    }

    /// Generic idempotent writer for the Phase 3 backfill (MigrationService).
    /// The caller composes the exact collection, doc id, and field map to match
    /// the schema, so historical CloudKit records land under the same doc ids
    /// the live dual-write uses. merge:true so re-running never clobbers.
    @discardableResult
    func backfillSet(collection: String, docID: String, data: [String: Any]) async -> Bool {
        do {
            try await db.collection(collection).document(docID).setData(data, merge: true)
            return true
        } catch {
            print("[Firebase] backfill \(collection)/\(docID) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// @ObservationIgnored is REQUIRED: the @Observable macro rewrites stored
    /// properties into computed ones with init accessors, and `lazy` cannot be
    /// applied to a computed property (build error). We never want to observe
    /// the Firestore handle anyway — only isReady/userID drive UI.
    @ObservationIgnored private lazy var db = Firestore.firestore()

    /// Forces the lazy singleton to initialize (kicking off anonymous
    /// sign-in). Call once from app launch after FirebaseApp.configure().
    func start() {}

    private init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.userID = user?.uid
                self?.isReady = user != nil
            }
        }
        Task { await signInIfNeeded() }
    }

    private func signInIfNeeded() async {
        guard Auth.auth().currentUser == nil else { return }
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("[Firebase] Anonymous sign-in succeeded: \(result.user.uid)")
        } catch {
            print("[Firebase] Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Common save pattern: log failures, ignore success.
    private func tryWrite(_ label: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            print("[Firebase] \(label) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Placements

    /// Upsert a placement. `note` mirrors CloudKit's read-modify-write: nil
    /// leaves the existing note untouched, a non-empty string sets it, and an
    /// empty/whitespace string clears it (FieldValue.delete()).
    func savePlacement(restaurantID: UUID, tier: Tier, note: String? = nil) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        var data: [String: Any] = [
            "userID": userID,
            "restaurantID": restaurantID.uuidString,
            "tier": tier.rawValue,
            "score": tier.score,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            data["note"] = trimmed.isEmpty ? FieldValue.delete() : trimmed
        }
        await tryWrite("savePlacement") {
            try await self.db.collection("placements").document(docID).setData(data, merge: true)
        }
    }

    /// Set/clear ONLY the note on an existing placement doc (mirrors
    /// CloudKitService.saveMyNote). Empty string clears it.
    func saveNote(restaurantID: UUID, note: String) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        await tryWrite("saveNote") {
            try await self.db.collection("placements").document(docID).setData([
                "note": trimmed.isEmpty ? FieldValue.delete() : trimmed,
            ], merge: true)
        }
    }

    func removePlacement(restaurantID: UUID) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        await tryWrite("removePlacement") {
            try await self.db.collection("placements").document(docID).delete()
        }
    }

    // MARK: - Closure reports (user-side)

    func saveClosureReport(restaurantID: UUID) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        await tryWrite("saveClosureReport") {
            try await self.db.collection("closureReports").document(docID).setData([
                "userID": userID,
                "restaurantID": restaurantID.uuidString,
                "createdAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    func deleteClosureReport(restaurantID: UUID) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        await tryWrite("deleteClosureReport") {
            try await self.db.collection("closureReports").document(docID).delete()
        }
    }

    // MARK: - Closure decisions (admin-side)

    func saveClosureDecision(restaurantID: UUID, decision: String) async {
        guard let userID = effectiveUserID else { return }
        await tryWrite("saveClosureDecision") {
            try await self.db.collection("closureDecisions")
                .document(restaurantID.uuidString)
                .setData([
                    "restaurantID": restaurantID.uuidString,
                    "decision": decision,            // "closed" | "open"
                    "decidedAt": FieldValue.serverTimestamp(),
                    "adminID": userID,
                ], merge: true)
        }
    }

    func deleteClosureDecision(restaurantID: UUID) async {
        await tryWrite("deleteClosureDecision") {
            try await self.db.collection("closureDecisions")
                .document(restaurantID.uuidString)
                .delete()
        }
    }

    // MARK: - Profiles (Foodie Pro request identity)

    /// `status` is optional: nil means "leave the existing status untouched"
    /// (used when CloudKit is unavailable so we can't read the current value —
    /// avoids downgrading an already-approved pro back to "" on a name edit).
    func saveProfile(displayName: String, status: String?) async {
        guard let userID = effectiveUserID else { return }
        var data: [String: Any] = [
            "userID": userID,
            "displayName": displayName,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let status { data["status"] = status }   // "" | "requested" | "approved"
        await tryWrite("saveProfile") {
            try await self.db.collection("profiles").document(userID).setData(data, merge: true)
        }
    }

    // MARK: - Pro approvals (admin-side)

    func saveProApproval(forUserID approvedUserID: String) async {
        guard let adminID = userID else { return }
        await tryWrite("saveProApproval") {
            try await self.db.collection("proApprovals").document(approvedUserID).setData([
                "userID": approvedUserID,
                "approvedAt": FieldValue.serverTimestamp(),
                "approvedBy": adminID,
            ], merge: true)
        }
    }

    func deleteProApproval(forUserID approvedUserID: String) async {
        await tryWrite("deleteProApproval") {
            try await self.db.collection("proApprovals").document(approvedUserID).delete()
        }
    }

    // MARK: - Photo reports (UGC moderation)

    func savePhotoReport(photoID: String) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(photoID)"
        await tryWrite("savePhotoReport") {
            try await self.db.collection("photoReports").document(docID).setData([
                "photoID": photoID,
                "reporterID": userID,
                "createdAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    // MARK: - Photo moderation (admin-side)

    func savePhotoModeration(photoID: String, decision: String) async {
        guard let adminID = userID else { return }
        await tryWrite("savePhotoModeration") {
            try await self.db.collection("photoModerated").document(photoID).setData([
                "photoID": photoID,
                "decision": decision,                // "hidden" | "approved"
                "decidedAt": FieldValue.serverTimestamp(),
                "adminID": adminID,
            ], merge: true)
        }
    }

    // MARK: - Suggestions (user-submitted missing restaurants)

    /// Returns the auto-generated document ID so the iOS code can pass
    /// it back to CloudKit if needed for cross-referencing during the
    /// soak period.
    func saveSuggestion(
        name: String,
        address: String,
        area: String,
        cuisines: [String],
        description: String
    ) async -> String? {
        guard let userID = effectiveUserID else { return nil }
        let docRef = db.collection("suggestions").document()
        do {
            try await docRef.setData([
                "name": name,
                "address": address,
                "area": area,
                "cuisines": cuisines,
                "description": description,
                "submitterUserID": userID,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp(),
            ])
            return docRef.documentID
        } catch {
            print("[Firebase] saveSuggestion failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Admin updates a suggestion's status — "approved" or "rejected".
    /// When approving, also creates the liveRestaurants doc.
    func updateSuggestionStatus(suggestionID: String, status: String) async {
        await tryWrite("updateSuggestionStatus") {
            try await self.db.collection("suggestions").document(suggestionID).setData([
                "status": status,
            ], merge: true)
        }
    }

    // MARK: - Live restaurants (admin-approved community additions)

    /// Mirrors CloudKitService.approveSuggestion's LiveRestaurant write.
    /// Takes the same fields as the iOS Restaurant model.
    func saveLiveRestaurant(
        restaurantID: UUID,
        suggestionID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        area: String,
        address: String,
        cuisines: [String],
        priceTier: String,
        isFastFood: Bool,
        description: String
    ) async {
        guard let adminID = userID else { return }
        await tryWrite("saveLiveRestaurant") {
            try await self.db.collection("liveRestaurants")
                .document(restaurantID.uuidString)
                .setData([
                    "name": name,
                    "latitude": latitude,
                    "longitude": longitude,
                    "area": area,
                    "address": address,
                    "cuisines": cuisines,
                    "priceTier": priceTier,
                    "isFastFood": isFastFood,
                    "description": description,
                    "signatureDishes": [String](),   // empty for community submissions
                    "approvedAt": FieldValue.serverTimestamp(),
                    "approvedBy": adminID,
                    "originalSuggestionID": suggestionID,
                ], merge: true)
        }
    }

    // MARK: - Visited list (per-user, single-doc-per-user)

    func saveVisitedList(_ restaurantIDs: Set<UUID>) async {
        guard let userID = effectiveUserID else { return }
        let ids = restaurantIDs.map { $0.uuidString }
        await tryWrite("saveVisitedList") {
            try await self.db.collection("visitedLists").document(userID).setData([
                "userID": userID,
                "restaurantIDs": ids,
                "count": ids.count,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    // MARK: - Dietary tags (mirrors CloudKitService.setDietaryTag)

    /// One doc per (user, restaurant, tag): `<uid>_<restaurant>_<tag>` so
    /// confirmations dedupe + count exactly like the CloudKit record.
    func setDietaryTag(restaurantID: UUID, tag: String, on: Bool) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)_\(tag)"
        if on {
            await tryWrite("setDietaryTag") {
                try await self.db.collection("dietaryTags").document(docID).setData([
                    "userID": userID,
                    "restaurantID": restaurantID.uuidString,
                    "tag": tag,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
            }
        } else {
            await tryWrite("removeDietaryTag") {
                try await self.db.collection("dietaryTags").document(docID).delete()
            }
        }
    }

    // MARK: - Friends / follow graph (mirrors CloudKitService.saveFriendList)

    /// Single doc per user holding the follow list, each entry encoded
    /// "userID|displayName" — same wire format as the CloudKit array.
    func saveFriendList(_ entries: [String]) async {
        guard let userID = effectiveUserID else { return }
        await tryWrite("saveFriendList") {
            try await self.db.collection("friendLists").document(userID).setData([
                "userID": userID,
                "entries": entries,
                "count": entries.count,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    // MARK: - Note reports (mirrors CloudKitService.reportNote)

    func saveNoteReport(placementRecordName: String) async {
        guard let userID = effectiveUserID else { return }
        let docID = "\(userID)_\(placementRecordName)"
        await tryWrite("saveNoteReport") {
            try await self.db.collection("noteReports").document(docID).setData([
                "placementName": placementRecordName,
                "reporterID": userID,
                "createdAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    // MARK: - Admin exclusions (mirrors ban/exclude/hide-note + their reversals)

    /// kind ∈ {"user","placement","note"}; docID `<kind>_<target>` matches the
    /// CloudKit recordName scheme so both stores stay addressable the same way.
    func saveExclusion(kind: String, target: String) async {
        guard let adminID = userID else { return }
        let docID = "\(kind)_\(target)"
        await tryWrite("saveExclusion(\(kind))") {
            try await self.db.collection("adminExclusions").document(docID).setData([
                "kind": kind,
                "target": target,
                "adminID": adminID,
                "createdAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    func deleteExclusion(kind: String, target: String) async {
        let docID = "\(kind)_\(target)"
        await tryWrite("deleteExclusion(\(kind))") {
            try await self.db.collection("adminExclusions").document(docID).delete()
        }
    }

    // MARK: - Reads (Phase 4 read-cutover, Part 1)
    //
    // Per-restaurant reads only — bounded and cheap on Firestore's per-doc
    // pricing (a restaurant's placements/tags, not the whole collection). The
    // full Community-board aggregate (all ~5.4K placements) is deliberately NOT
    // here: scanning every placement per board load is expensive, and Part 2
    // will back it with a maintained per-restaurant consensus doc (or a Cloud
    // Function) before that read is cut over. These are gated behind an
    // admin-only kill-switch in CloudKitService; default is CloudKit reads.

    /// Coerce a Firestore numeric (Int64 / NSNumber / Double) to Int.
    private func intOf(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let i = v as? Int64 { return Int(i) }
        if let n = v as? NSNumber { return n.intValue }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    @ObservationIgnored private var exclBannedUsers: Set<String> = []
    @ObservationIgnored private var exclPlacementNames: Set<String> = []
    @ObservationIgnored private var exclLoaded = false

    /// Load the admin-exclusion sets once (banned users + individually excluded
    /// placements) so community aggregates filter identically to CloudKit.
    /// Placement exclusions target the CloudKit placement recordName
    /// ("placement_<user>_<restaurant>"), which we reconstruct from each
    /// Firestore doc's userID + restaurantID.
    func loadExclusionsIfNeeded(force: Bool = false) async {
        guard force || !exclLoaded else { return }
        do {
            let snap = try await db.collection("adminExclusions").getDocuments()
            var banned: Set<String> = []
            var placements: Set<String> = []
            for doc in snap.documents {
                guard let kind = doc.get("kind") as? String,
                      let target = doc.get("target") as? String else { continue }
                if kind == "user" { banned.insert(target) }
                else if kind == "placement" { placements.insert(target) }
            }
            exclBannedUsers = banned
            exclPlacementNames = placements
            exclLoaded = true
        } catch {
            // Leave caches as-is; aggregates fall back to unfiltered.
        }
    }

    /// Consensus tier for one restaurant from everyone's placements. Applies the
    /// same admin exclusions as CloudKit. nil if no one has ranked it.
    func fetchCommunityTier(restaurantID: UUID) async -> CommunityTier? {
        await loadExclusionsIfNeeded()
        let rid = restaurantID.uuidString
        do {
            let snap = try await db.collection("placements")
                .whereField("restaurantID", isEqualTo: rid)
                .getDocuments()
            var total = 0
            var count = 0
            for doc in snap.documents {
                guard let score = intOf(doc.get("score")) else { continue }
                let owner = doc.get("userID") as? String ?? ""
                if exclBannedUsers.contains(owner) { continue }
                if exclPlacementNames.contains("placement_\(owner)_\(rid)") { continue }
                total += score
                count += 1
            }
            guard count > 0 else { return nil }
            let avg = Double(total) / Double(count)
            return CommunityTier(tier: .from(averageScore: avg), count: count, average: avg)
        } catch {
            return nil
        }
    }

    /// Community dietary-tag counts for one restaurant + the tags the current
    /// user confirmed. Keyed by DietaryTag raw value (matches CloudKit).
    func fetchDietaryTags(restaurantID: UUID) async -> (counts: [String: Int], mine: Set<String>) {
        let me = effectiveUserID
        do {
            let snap = try await db.collection("dietaryTags")
                .whereField("restaurantID", isEqualTo: restaurantID.uuidString)
                .getDocuments()
            var counts: [String: Int] = [:]
            var mine: Set<String> = []
            for doc in snap.documents {
                guard let tag = doc.get("tag") as? String else { continue }
                counts[tag, default: 0] += 1
                if let uid = doc.get("userID") as? String, uid == me { mine.insert(tag) }
            }
            return (counts, mine)
        } catch {
            return ([:], [])
        }
    }
}
