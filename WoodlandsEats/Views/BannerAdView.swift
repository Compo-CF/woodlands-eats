import SwiftUI
import GoogleMobileAds
import UIKit

/// v1.7 Feature D: drop-in replacement for `BannerAdView` that hides
/// the banner — frame, material background, and all — when the user
/// has bought the ad-free upgrade. Returns EmptyView in that case so
/// the .safeAreaInset doesn't reserve 50pt of empty thin-material bar
/// at the bottom of the screen.
struct MaybeBannerAd: View {
    @Environment(PurchaseStore.self) private var purchases
    var body: some View {
        if !purchases.isAdFree {
            BannerAdView()
                .frame(height: 50)
                .background(.thinMaterial)
        }
    }
}

/// SwiftUI wrapper around `GADBannerView` for the standard 320x50 banner
/// at the bottom of the Browse and Map tabs. Uses non-personalized ads
/// (no ATT prompt).
///
/// Production ad unit for S-Tier Eats (registered standalone in AdMob,
/// distinct from the Fishing app's unit — AdMob server-side binds unit
/// IDs to the registered app's bundle ID at request time, so reuse across
/// bundle IDs returns no-fill):
///   ca-app-pub-1927040492403163/8897080292
///
/// Override the default to test with Google's published test unit
/// (`ca-app-pub-3940256099942544/2934735716`) if needed during local dev.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String = "ca-app-pub-1927040492403163/8897080292") {
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
