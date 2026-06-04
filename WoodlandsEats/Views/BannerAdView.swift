import SwiftUI
import GoogleMobileAds
import UIKit

/// SwiftUI wrapper around `GADBannerView` for the standard 320x50 banner
/// at the bottom of the Browse tab. Uses non-personalized ads (no ATT
/// prompt) and the AdMob test ad unit by default.
///
/// Production ad unit (shared with the Woodlands Fishing app):
///   ca-app-pub-1927040492403163/4580765066
///
/// Override the default to test with Google's published test unit
/// (`ca-app-pub-3940256099942544/2934735716`) if needed during local dev.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String = "ca-app-pub-1927040492403163/4580765066") {
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
