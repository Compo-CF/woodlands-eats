import Foundation
import GoogleMobileAds

/// Centralized AdMob lifecycle.
///
/// Initialize once on app launch. Every ad request goes through
/// `nonPersonalizedRequest()` so we never need the App Tracking
/// Transparency popup — opt-in rates are 30-40% industry-wide, so
/// avoiding the prompt is worth the ~50% CPM hit on non-personalized
/// ads for a small-audience local app like this one.
///
/// Test IDs (publishable, no AdMob account required during development):
///   App ID:        ca-app-pub-3940256099942544~1458002511   (Info.plist)
///   Banner unit:   ca-app-pub-3940256099942544/2934735716   (BannerAdView)
///
/// When AdMob is set up for production, swap the App ID in project.yml
/// (GADApplicationIdentifier) and the banner adUnitID in BannerAdView.
final class AdsService {
    static let shared = AdsService()
    private init() {}

    /// Boot the Google Mobile Ads SDK. Safe to call on the main thread.
    func start() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    /// Build a request flagged as non-personalized (NPA=1). The SDK still
    /// shows ads, but Google's targeting falls back to contextual signals
    /// rather than user-level tracking — no IDFA, no ATT prompt.
    func nonPersonalizedRequest() -> GADRequest {
        let extras = GADExtras()
        extras.additionalParameters = ["npa": "1"]
        let request = GADRequest()
        request.register(extras)
        return request
    }
}
