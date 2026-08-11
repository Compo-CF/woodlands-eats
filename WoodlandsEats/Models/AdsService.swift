import Foundation
import GoogleMobileAds

/// Centralized AdMob lifecycle.
///
/// Initialize once on app launch. Every ad request is non-personalized
/// (NPA=1) — the app does NOT track users, so there's no ATT prompt and no
/// IDFA use. (v2.2 briefly added ATT/personalized ads; removed after App
/// Review 2.1 flagged the prompt and the personalized-ads upside was
/// negligible at this volume. The privacy label declares no tracking.)
///
/// Ad content is also capped to `.general` (see start()) — without it,
/// AdMob's default targeting can serve adult/dating/suggestive creative
/// with no relation to a food/restaurant app.
///
/// Test IDs (publishable, no AdMob account required during development):
///   App ID:        ca-app-pub-3940256099942544~1458002511   (Info.plist)
///   Banner unit:   ca-app-pub-3940256099942544/2934735716   (BannerAdView)
final class AdsService {
    static let shared = AdsService()
    private init() {}

    /// Boot the Google Mobile Ads SDK. Safe to call on the main thread.
    func start() {
        // Must be set before start() — applies to every ad request for the
        // lifetime of the process, banner or otherwise.
        GADMobileAds.sharedInstance().requestConfiguration.maxAdContentRating = .general
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    /// The request to use for every ad load — always non-personalized.
    func adRequest() -> GADRequest { nonPersonalizedRequest() }

    /// Build a request flagged as non-personalized (NPA=1). Ads still show,
    /// but Google's targeting uses contextual signals only — no IDFA, no
    /// ATT prompt, no tracking.
    func nonPersonalizedRequest() -> GADRequest {
        let extras = GADExtras()
        extras.additionalParameters = ["npa": "1"]
        let request = GADRequest()
        request.register(extras)
        return request
    }
}
