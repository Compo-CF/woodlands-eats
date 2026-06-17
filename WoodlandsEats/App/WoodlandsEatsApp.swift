import SwiftUI

@main
struct WoodlandsEatsApp: App {
    @State private var store = RestaurantStore()
    @State private var tierStore = TierListStore()
    @State private var locationManager = LocationManager()
    @State private var cloudKit = CloudKitService()
    @State private var blockList = BlockListStore()
    @State private var visitedStore = VisitedStore()
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
