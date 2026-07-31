import Foundation
import GoogleMobileAds
import AppTrackingTransparency

/// Centralized AdMob lifecycle.
///
/// Initialize once on app launch.
///
/// v2.2 (AdMob revenue): ad requests now follow App Tracking Transparency.
/// `adRequest()` returns a PERSONALIZED request when the user has granted
/// tracking (higher eCPM), and falls back to the non-personalized (NPA)
/// request otherwise. The ATT system prompt is triggered once, after a
/// short in-app priming step (see TrackingPrimingView / ContentView), so we
/// only pay the "explain why" cost when it can actually lift revenue.
///
/// Test IDs (publishable, no AdMob account required during development):
///   App ID:        ca-app-pub-3940256099942544~1458002511   (Info.plist)
///   Banner unit:   ca-app-pub-3940256099942544/2934735716   (BannerAdView)
final class AdsService {
    static let shared = AdsService()
    private init() {}

    /// Boot the Google Mobile Ads SDK. Safe to call on the main thread.
    func start() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    /// The request to use for every ad load. Personalized when ATT is
    /// authorized (Google can use the IDFA for user-level targeting →
    /// higher CPM); non-personalized in every other state (denied,
    /// restricted, or not-yet-determined).
    func adRequest() -> GADRequest {
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
            return GADRequest()   // personalized
        }
        return nonPersonalizedRequest()
    }

    /// Build a request flagged as non-personalized (NPA=1). The SDK still
    /// shows ads, but Google's targeting falls back to contextual signals
    /// rather than user-level tracking — no IDFA.
    func nonPersonalizedRequest() -> GADRequest {
        let extras = GADExtras()
        extras.additionalParameters = ["npa": "1"]
        let request = GADRequest()
        request.register(extras)
        return request
    }

    /// Present the system ATT prompt if the user hasn't answered yet. Call
    /// this AFTER the in-app priming screen so the user understands the ask.
    /// The OS shows the prompt at most once per install; subsequent calls
    /// no-op and just return the stored status.
    @MainActor
    func requestTrackingIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}
