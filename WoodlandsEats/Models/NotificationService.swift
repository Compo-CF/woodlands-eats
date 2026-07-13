import Foundation
import UserNotifications
import CloudKit
import UIKit

/// v1.9: push notifications, CloudKit-native (no backend server).
///
/// Two CKQuerySubscriptions, both fire-on-create, deliver APNs alerts
/// through CloudKit's own push infrastructure:
///
///   1. New restaurant (global) — a CKQuerySubscription on LiveRestaurant.
///      When the admin approves a community suggestion (creates a
///      LiveRestaurant), every opted-in user gets "A new spot was just
///      added — come rank it." New-restaurant events are admin-gated and
///      rare, so this is low-frequency / high-relevance — the right
///      profile for a re-engagement nudge.
///
///   2. Foodie Pro approval (personal) — a CKQuerySubscription on
///      ProApproval filtered to the current user's approval record. Fires
///      once, when the admin approves THIS user, delivering
///      "You're now a Foodie Pro!"
///
/// Opt-in: gated behind an explicit Profile toggle so we request
/// notification permission contextually (not a cold first-launch prompt,
/// which tanks acceptance and irritates App Review). The @AppStorage
/// flag persists the user's choice.
///
/// Subscription saves are idempotent — fixed subscription IDs mean
/// re-registering on every launch just replaces the existing record.
/// CloudKit push delivery is handled server-side by Apple; the app only
/// needs a successful remote-notification registration + the subscription
/// records to exist.
@Observable
@MainActor
final class NotificationService {
    /// User's opt-in choice. Also the source of truth the Profile toggle binds to.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) }
    }
    /// Live authorization status from the system (mirrors UNNotificationSettings).
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// v2.1: set when the user taps a "new restaurant" push. ContentView
    /// observes this and presents that restaurant's detail, then clears it.
    var pendingRestaurantID: UUID?

    /// v2.1: bridge so the UIApplicationDelegate (which lives outside the
    /// SwiftUI environment) can hand notification taps to the live service
    /// instance. Set in init; there's only ever one NotificationService.
    static weak var shared: NotificationService?

    private let enabledKey = "WoodlandsEats.notificationsEnabled"
    private let newRestaurantSubID = "sub-new-restaurant-v1"
    private let proApprovalSubIDPrefix = "sub-pro-approval-"

    private var container: CKContainer { CKContainer.default() }
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    init() {
        enabled = UserDefaults.standard.bool(forKey: enabledKey)
        NotificationService.shared = self
    }

    /// v2.1: handle a tapped notification. For the new-restaurant push, the
    /// CloudKit payload carries the LiveRestaurant recordID ("live_<uuid>");
    /// we extract the UUID so ContentView can open that restaurant. The Pro-
    /// approval push has no deep link (it just re-engages), so it's ignored.
    func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let name = note.recordID?.recordName,
              name.hasPrefix("live_"),
              let uuid = UUID(uuidString: String(name.dropFirst("live_".count)))
        else { return }
        pendingRestaurantID = uuid
    }

    /// Refresh the cached authorization status from the system.
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Called on launch: if the user previously opted in AND the OS still
    /// grants permission, make sure the subscriptions exist (idempotent).
    /// Does NOT prompt — prompting only happens from the explicit toggle.
    func syncOnLaunch(currentUserID: String?) async {
        await refreshAuthorization()
        guard enabled, authorization == .authorized else { return }
        await registerForRemoteNotifications()
        await ensureSubscriptions(currentUserID: currentUserID)
    }

    /// Toggle handler: turning ON requests permission (if needed) then
    /// registers subscriptions; turning OFF deletes them so the user
    /// stops receiving pushes immediately.
    func setEnabled(_ on: Bool, currentUserID: String?) async {
        enabled = on
        if on {
            let granted = await requestAuthorization()
            guard granted else {
                // User denied at the system prompt — reflect reality.
                enabled = false
                await refreshAuthorization()
                return
            }
            await registerForRemoteNotifications()
            await ensureSubscriptions(currentUserID: currentUserID)
        } else {
            await removeSubscriptions(currentUserID: currentUserID)
        }
    }

    /// Ask the system for alert/sound/badge permission. Returns whether granted.
    private func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Register with APNs. CloudKit routes pushes through APNs, so the
    /// app must have completed remote-notification registration at least
    /// once. The device token itself isn't used by our code — CloudKit
    /// tracks it — so we just trigger registration on the main thread.
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Create (or replace) both subscriptions. Idempotent via fixed IDs.
    private func ensureSubscriptions(currentUserID: String?) async {
        var subs: [CKSubscription] = [newRestaurantSubscription()]
        if let uid = currentUserID, !uid.isEmpty {
            subs.append(proApprovalSubscription(userID: uid))
        }
        for sub in subs {
            do {
                _ = try await publicDB.save(sub)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Subscription with this ID already exists — that's fine,
                // it means we're already subscribed. Ignore.
            } catch {
                // Network / transient — will retry next launch via syncOnLaunch.
            }
        }
    }

    private func removeSubscriptions(currentUserID: String?) async {
        var ids = [newRestaurantSubID]
        if let uid = currentUserID, !uid.isEmpty {
            ids.append(proApprovalSubIDPrefix + uid)
        }
        for id in ids {
            _ = try? await publicDB.deleteSubscription(withID: id)
        }
    }

    // ─── Subscription builders ───────────────────────────────────────

    private func newRestaurantSubscription() -> CKQuerySubscription {
        let sub = CKQuerySubscription(
            recordType: "LiveRestaurant",
            predicate: NSPredicate(value: true),
            subscriptionID: newRestaurantSubID,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "A new restaurant was just added to S-Tier Eats — open the app to rank it."
        info.soundName = "default"
        info.shouldBadge = true
        sub.notificationInfo = info
        return sub
    }

    private func proApprovalSubscription(userID: String) -> CKQuerySubscription {
        // ProApproval recordName is "approval_<userID>"; filter to this
        // user so the push only fires for THEIR approval, not everyone's.
        let sub = CKQuerySubscription(
            recordType: "ProApproval",
            predicate: NSPredicate(format: "userID == %@", userID),
            subscriptionID: proApprovalSubIDPrefix + userID,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "You're now a Foodie Pro! Your rankings now power the Pros leaderboard."
        info.soundName = "default"
        info.shouldBadge = true
        sub.notificationInfo = info
        return sub
    }
}
