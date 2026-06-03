import SwiftUI
import GoogleMobileAds
import UIKit

/// SwiftUI wrapper around `GADBannerView` for the standard 320x50 banner
/// at the bottom of the Browse tab. Uses non-personalized ads (no ATT
/// prompt) and the AdMob test ad unit by default.
///
/// Test ad unit (no AdMob account required during development):
///   ca-app-pub-3940256099942544/2934735716
///
/// When AdMob is set up for production, pass the real ad unit ID to the
/// initializer. The banner displays test mockups against the test ID and
/// real inventory against a production ID — no other code change needed.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String = "ca-app-pub-3940256099942544/2934735716") {
        self.adUnitID = adUnitID
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)   // standard 320x50
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(AdsService.shared.nonPersonalizedRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // Re-attach the root view controller in case the scene changed.
        uiView.rootViewController = Self.topViewController()
    }

    /// AdMob needs a rootViewController to host the click-through web view
    /// when the user taps a banner. Walk the active scene's window hierarchy
    /// to find one. Safe to call on the main thread.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
    }
}
