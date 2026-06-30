import SwiftUI
// v1.6 (Android migration A2): Firebase Core for SDK initialization.
// Reads GoogleService-Info.plist from the bundle to wire up the
// project ID, API key, and Firebase service endpoints.
import FirebaseCore

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()
    @State private var visitedStore = VisitedStore()
    /// v1.6 (Android migration A2): cross-platform data layer.
    /// Currently dual-writes alongside CloudKit; reads cut over to
    /// Firestore in v1.7. Created after FirebaseApp.configure() so
    /// it can safely use Firebase SDK in its init.
    @State private var firebase = FirebaseService()
    /// v1.5: routes programmatic tab switches (e.g., the rank-icon
    /// shortcut on Map/Browse → Profile). Injected via .environment
    /// so any child view can change `selectedTab`.
    @State private var tabRouter = TabRouter()
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
        // v1.6 (Android migration A2): Firebase must be configured
        // before any Firebase SDK call (Auth, Firestore, Storage).
        // FirebaseApp.configure() reads GoogleService-Info.plist from
        // the bundle. Idempotent — safe to call multiple times, but we
        // only call once here at app boot. Goes FIRST in init() so any
        // downstream service initializers can safely reference Firebase.
        FirebaseApp.configure()

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
                    .environment(tabRouter)
                    .environment(firebase)
                    .onChange(of: locationManager.location) { _, newValue in
                        store.userLocation = newValue
                    }
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { if !$0 { hasCompletedOnboarding = true } }
                    )) {
                        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                            .environment(locationManager)
                    }
            } else {
                EULAView(hasAccepted: $hasAcceptedEULA)
            }
        }
    }
}
