import Foundation
import UserNotifications

/// v3.1 — local notifications core (see `docs/3.1-notifications-plan.md`, Phase A).
///
/// On-device scheduling only, no backend. This file implements **A1 — the weekly Night Out
/// reminder** end to end and leaves A2/A3/A4 as clearly-marked stubs so the shape is in place.
///
/// WIRING (3 touch points — marked `// WIRE:` below):
///   1. App launch: `NotificationScheduler.shared.registerAsDelegate()` then
///      `Task { await NotificationScheduler.shared.rescheduleAll() }`. Call `rescheduleAll()`
///      again on `scenePhase == .active` — iOS drops pending requests past a cap, so we re-assert.
///   2. After a value moment (3rd rank / list created / friend invited): show a custom explainer
///      sheet, and only if the user taps "Turn on" call `await requestAuthorization()`.
///   3. Provide the live ranked-spot count via `rankedSpotCount` so Night Out only schedules once
///      the user actually has tiers to plan from.
///
/// Settings → Notifications: a SwiftUI view binds each toggle with
/// `@AppStorage(NotificationScheduler.Kind.nightOut.defaultsKey)` etc. + the master key, and calls
/// `Task { await NotificationScheduler.shared.rescheduleAll() }` on change.
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationScheduler()
    private override init() { super.init() }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    // MARK: - Routes (deep links a tapped notification opens)

    /// These mirror the app's existing `stier://` scheme (`stier://tier/<uid>` already works).
    /// `stier://nightout` and `stier://community` must be added to the deep-link handler.
    enum Route: String {
        case nightOut  = "stier://nightout"
        case newSpots  = "stier://new"
        case community = "stier://community"
    }

    // MARK: - Notification kinds

    enum Kind: String, CaseIterable {
        case nightOut        // A1 — weekly "plan a night out"      (implemented)
        case newSpots        // A2 — new openings (catalog diff)    (TODO)
        case weeklyCheckIn   // A3 — "rank where you ate"           (TODO)
        case lapsed          // A4 — re-engagement                  (TODO)

        /// UserDefaults key for this type's on/off toggle (also used by `@AppStorage` in Settings).
        var defaultsKey: String { "notif.\(rawValue).enabled" }
        /// Stable request identifier so we can replace (not duplicate) on every reschedule.
        var identifier: String { "stier.notif.\(rawValue)" }

        var title: String {
            switch self {
            case .nightOut:      return "Where to tonight?"
            case .newSpots:      return "New in The Woodlands"
            case .weeklyCheckIn: return "Been out this week?"
            case .lapsed:        return "The scene moved while you were gone"
            }
        }
        var body: String {
            switch self {
            case .nightOut:      return "Plan a night out from your S & A tiers."
            case .newSpots:      return "New spots just landed — rank them."
            case .weeklyCheckIn: return "Add this week's spots to your tiers."
            case .lapsed:        return "See what The Woodlands is ranking now."
            }
        }
        var route: Route {
            switch self {
            case .nightOut:                 return .nightOut
            case .newSpots:                 return .newSpots
            case .weeklyCheckIn, .lapsed:   return .community
            }
        }
    }

    // MARK: - Preferences (default ON; master gate + per-type)

    static let masterDefaultsKey = "notif.master.enabled"

    var masterEnabled: Bool { defaults.object(forKey: Self.masterDefaultsKey) as? Bool ?? true }
    func isEnabled(_ kind: Kind) -> Bool { defaults.object(forKey: kind.defaultsKey) as? Bool ?? true }

    // MARK: - Dependencies to inject

    /// WIRE 3: return the user's current ranked-spot count (e.g. from CloudKitService/placements).
    /// Night Out stays unscheduled until this is >= `minRankedForNightOut`.
    var rankedSpotCount: () -> Int = { 0 }
    private let minRankedForNightOut = 3

    // MARK: - Delegate registration

    /// WIRE 1: call once at launch.
    func registerAsDelegate() { center.delegate = self }

    // MARK: - Permission

    /// WIRE 2: call only after a value moment, behind your own explainer sheet. Never on first launch.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await rescheduleAll()
        return granted
    }

    private func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// True if the user hasn't been asked yet — so a value-moment explainer is appropriate.
    func isUndetermined() async -> Bool { await authorizationStatus() == .notDetermined }

    // MARK: - Scheduling

    /// Re-assert every enabled repeating notification we own. Safe to call often (launch + foreground).
    func rescheduleAll() async {
        let status = await authorizationStatus()
        let allowed = masterEnabled && (status == .authorized || status == .provisional)

        // Only ever touch the identifiers we own.
        center.removePendingNotificationRequests(withIdentifiers: Kind.allCases.map(\.identifier))
        guard allowed else { return }

        if isEnabled(.nightOut) { await scheduleNightOut() }
        // TODO A2: if isEnabled(.newSpots)      { await scheduleNewSpots() }       // catalog-diff after an update
        // TODO A3: if isEnabled(.weeklyCheckIn) { await scheduleWeeklyCheckIn() }  // suppress if ranked in last 3 days
        // TODO A4: if isEnabled(.lapsed)        { await scheduleLapsed() }         // fire only after 10 idle days
    }

    /// A1 — weekly Night Out reminder: Thursday 4:30pm local, repeating.
    private func scheduleNightOut() async {
        guard rankedSpotCount() >= minRankedForNightOut else { return }
        let kind = Kind.nightOut

        var when = DateComponents()
        when.weekday = 5   // Sunday = 1 … Thursday = 5
        when.hour = 16
        when.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default
        content.userInfo = ["route": kind.route.rawValue]

        let request = UNNotificationRequest(identifier: kind.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Tap handling → deep link

    /// Last route from a tapped notification (read on launch in case the app wasn't running).
    static var pendingRoute: URL?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["route"] as? String,
           let url = URL(string: raw) {
            // WIRE 1 (cont.): route through the app's existing stier:// handler — the same path used
            // for stier://tier/<uid>. For now we stash it + post a notification the App can observe.
            Self.pendingRoute = url
            NotificationCenter.default.post(name: .stierOpenRoute, object: url)
        }
        completionHandler()
    }

    /// Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    /// Posted with a `stier://` URL when a notification is tapped; the App observes it to deep-link.
    static let stierOpenRoute = Notification.Name("stier.openRoute")
}
