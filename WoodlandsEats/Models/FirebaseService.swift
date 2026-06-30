import Foundation
import FirebaseAuth
import FirebaseFirestore
import Observation

/// v1.6 (Android migration A2): the cross-platform data layer.
/// Mirrors CloudKitService's public API one method at a time as we
/// dual-write each operation. Reads still come from CloudKit during
/// the soak period (v1.6); Firestore reads turn on in v1.7.
///
/// Identity model:
///   - On first launch we anonymously sign in with Firebase Auth.
///     The resulting UID is the user's identifier on the Firestore
///     side (replaces CloudKit's iCloud userRecordName).
///   - This first iteration is per-device — each install gets its
///     own UID. Cross-device identity broker (iCloud KVS) lands in
///     a follow-up commit after we verify the basic write pipeline.
///
/// Schema reference: docs/firestore-schema.md
///
/// State exposure (for views via @Environment):
///   - `isReady` flips to true once Firebase Auth resolves
///   - `userID` is the current Firebase UID (nil until auth resolves)
/// Both update on the main actor so SwiftUI observation picks them up.
@Observable
final class FirebaseService {
    private(set) var isReady = false
    private(set) var userID: String?

    private let db = Firestore.firestore()

    init() {
        // Listen for auth state changes. Fires immediately with current
        // user (if any) and again on sign-in/sign-out events.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Auth callbacks come on a background queue; route to main
            // so @Observable mutations trigger SwiftUI updates correctly.
            DispatchQueue.main.async {
                self?.userID = user?.uid
                self?.isReady = user != nil
            }
        }
        // Kick off anonymous sign-in if no current user. Fire-and-forget;
        // the addStateDidChangeListener above picks up the result.
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

    // MARK: - Placements (dual-write target for CloudKitService.savePlacement)

    /// Mirrors CloudKitService.savePlacement. Writes to the
    /// `placements` collection with composite doc ID
    /// `{userID}_{restaurantID}` so the same record is identified
    /// across both backends.
    /// Fire-and-forget: failures are logged but don't propagate. The
    /// CloudKit write is still authoritative through v1.7.
    func savePlacement(restaurantID: UUID, tier: Tier) async {
        guard let userID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        do {
            try await db.collection("placements").document(docID).setData([
                "userID": userID,
                "restaurantID": restaurantID.uuidString,
                "tier": tier.rawValue,
                "score": tier.score,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        } catch {
            print("[Firebase] savePlacement failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors CloudKitService.removePlacement. Deletes the doc by
    /// composite ID.
    func removePlacement(restaurantID: UUID) async {
        guard let userID else { return }
        let docID = "\(userID)_\(restaurantID.uuidString)"
        do {
            try await db.collection("placements").document(docID).delete()
        } catch {
            print("[Firebase] removePlacement failed: \(error.localizedDescription)")
        }
    }
}
