import SwiftUI
import UserNotifications
// v2.5 (Android migration): Firebase Core to initialize the SDK before any
// Firestore/Auth call. Reads GoogleService-Info.plist from the bundle.
import FirebaseCore

/// v1.9: minimal AppDelegate so SwiftUI can complete APNs registration
/// and present CloudKit-driven notifications while the app is foreground.
/// CloudKit handles push delivery server-side; we just need registration
/// to succeed and a delegate to control foreground presentation.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Registration succeeded — CloudKit tracks the token itself, so no work needed.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] remote registration failed: \(error.localizedDescription)")
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // v2.1: user tapped a notification — route new-restaurant pushes to that
    // restaurant's detail via the shared NotificationService.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        // handleNotificationTap is a synchronous @MainActor method, so hop to
        // the main actor explicitly (await MainActor.run) rather than awaiting
        // the call itself — avoids the "no async operations" warning.
        await MainActor.run {
            NotificationService.shared?.handleNotificationTap(userInfo)
        }
    }
}

@main
struct WoodlandsEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()
    @State private var visitedStore = VisitedStore()
    /// v2.0 Feature 3: persistent follow graph. Restored from CloudKit at
    /// launch (see ContentView.task).
    @State private var friendsStore = FriendsStore()
    /// v1.5: routes programmatic tab switches (e.g., the rank-icon
    /// shortcut on Map/Browse → Profile). Injected via .environment
    /// so any child view can change `selectedTab`.
    @State private var tabRouter = TabRouter()
    /// v1.7 Feature B: Sign in with Apple service — layered on top of
    /// CloudKit identity. Restores persisted user ID + name on init,
    /// refreshes credential state on launch (handles Apple-side revocation).
    @State private var appleSignIn = AppleSignInService()
    /// v1.7 Feature D: In-app purchase store for the $1.99 ad-free
    /// upgrade. Fetches product + entitlement state on launch; gates
    /// MaybeBannerAd visibility on isAdFree.
    @State private var purchaseStore = PurchaseStore()
    /// v1.9: push notifications (CloudKit CKQuerySubscriptions).
    /// Opt-in via Profile toggle; re-syncs subscriptions on launch.
    @State private var notifications = NotificationService()
    /// v1.7 Feature C: User ID parsed out of an incoming friend-tier
    /// universal link. When non-nil, FriendTierView is presented as a
    /// sheet over ContentView. Cleared when the user dismisses.
    @State private var friendTierUserID: String?
    /// App Review Guideline 1.2 (UGC) requires an EULA gate that the user must
    /// accept before using the app. Persisted in @AppStorage so it survives
    /// launches but resets on uninstall — the latter is intentional so a fresh
    /// install presents the EULA again. Until the flag flips, the EULAView
    /// fully replaces ContentView.
    @AppStorage("WoodlandsEats.hasAcceptedEULA") private var hasAcceptedEULA = false
    /// v1.3: three-screen onboarding flow gate. False on fresh install →
    /// OnboardingView covers ContentView until completed. Migration logic
    /// for users coming from v1.2 (who saw the old tier-guide sheet) lives
    /// in ContentView's onAppear — they get auto-marked as onboarded.
    @AppStorage("WoodlandsEats.hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    init() {
        // v2.5 (Android migration): Firebase MUST be configured before any
        // Firebase SDK call. Goes first so the FirebaseService singleton (and
        // any dual-write) can safely touch Firestore/Auth. Idempotent.
        FirebaseApp.configure()
        FirebaseService.shared.start()   // trigger anon sign-in

        // v1.3 migration: existing pre-v1.3 users who already saw the
        // old tier-guide first-launch sheet shouldn't get the new
        // OnboardingView on upgrade. Do this in init via direct
        // UserDefaults access (NOT @AppStorage in ContentView.onAppear)
        // so the migration completes BEFORE the .fullScreenCover binding
        // reads hasCompletedOnboarding — otherwise upgraders see a
        // brief flash of OnboardingView that then auto-dismisses.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "WoodlandsEats.hasSeenTierGuide")
            && !defaults.bool(forKey: "WoodlandsEats.hasCompletedOnboarding") {
            defaults.set(true, forKey: "WoodlandsEats.hasCompletedOnboarding")
        }
        // v1.1: boot AdMob early so the first banner load on the Browse
        // tab is warm. Safe to call repeatedly; the SDK no-ops if already
        // initialized.
        AdsService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            if hasAcceptedEULA {
                ContentView()
                    .environment(store)
                    .environment(tierStore)
                    .environment(locationManager)
                    .environment(cloudKit)
                    .environment(blockList)
                    .environment(visitedStore)
                    .environment(friendsStore)
                    .environment(tabRouter)
                    .environment(appleSignIn)
                    .environment(purchaseStore)
                    .environment(notifications)
                    .task {
                        // v1.7 Feature B: check Apple's view of the
                        // credential on each cold launch. If they revoked
                        // server-side (e.g. user removed our app from
                        // their Apple ID sign-in list), sign the user
                        // out locally so the UI doesn't lie about being
                        // authenticated.
                        await appleSignIn.refreshCredentialState()
                        // v1.9: if the user opted into push and the OS
                        // still grants it, make sure the CloudKit
                        // subscriptions exist. No prompt here — the
                        // permission ask only happens from the Profile
                        // toggle. Runs after currentUserID resolves so
                        // the personal Pro-approval subscription targets
                        // the right account.
                        let uid = await cloudKit.currentUserID()
                        await notifications.syncOnLaunch(currentUserID: uid)
                    }
                    // v1.7 Feature C: friend-tier deep links. Two flavors
                    // accepted:
                    //   - https://compo-cf.github.io/woodlands-eats/tier/<id>
                    //     (Universal Link — preferred for sharing)
                    //   - stier://tier/<id> (custom-scheme fallback)
                    .onOpenURL { url in
                        if let id = parseFriendTierID(from: url) {
                            friendTierUserID = id
                        }
                    }
                    .sheet(item: Binding<FriendTierLinkID?>(
                        get: { friendTierUserID.map(FriendTierLinkID.init) },
                        set: { friendTierUserID = $0?.value }
                    )) { link in
                        FriendTierView(userID: link.value)
                            .environment(cloudKit)
                            .environment(store)
                            .environment(friendsStore)
                            .environment(tierStore)
                    }
                    .onChange(of: locationManager.location) { _, newValue in
                        store.userLocation = newValue
                    }
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { if !$0 { hasCompletedOnboarding = true } }
                    )) {
                        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                            .environment(locationManager)
                            .environment(purchaseStore)
                    }
            } else {
                EULAView(hasAccepted: $hasAcceptedEULA)
            }
        }
    }

    /// v1.7 Feature C: Pull the userRecordName out of an incoming deep
    /// link. Tolerant — returns nil for unrelated URLs.
    /// Accepted shapes:
    ///   https://compo-cf.github.io/woodlands-eats/tier/<id>
    ///   stier://tier/<id>
    private func parseFriendTierID(from url: URL) -> String? {
        if url.scheme == "stier", url.host == "tier" {
            let parts = url.pathComponents.filter { $0 != "/" }
            return parts.first
        }
        if url.scheme == "https" || url.scheme == "http" {
            let parts = url.pathComponents
            if let idx = parts.firstIndex(of: "tier"), idx + 1 < parts.count {
                let id = parts[idx + 1]
                return id.isEmpty ? nil : id
            }
        }
        return nil
    }
}

/// Identifiable wrapper so the friend-tier-user-id string can drive a
/// SwiftUI .sheet(item:) binding. (Plain Strings aren't Identifiable.)
private struct FriendTierLinkID: Identifiable {
    let value: String
    var id: String { value }
}
