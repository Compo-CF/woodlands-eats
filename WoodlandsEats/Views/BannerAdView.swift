import SwiftUI
import GoogleMobileAds
import UIKit

/// v1.7 Feature D: drop-in replacement for `BannerAdView` that hides
/// the banner — frame, material background, and all — when the user
/// has bought the ad-free upgrade. Returns EmptyView in that case so
/// the .safeAreaInset doesn't reserve an empty thin-material bar at the
/// bottom of the screen.
///
/// v2.2 (AdMob revenue): switched from the fixed 320x50 banner to an
/// anchored ADAPTIVE banner sized to the device width. Adaptive banners
/// are taller/relevant per device and reliably earn a higher eCPM than
/// the legacy fixed size, so the reserved height is now computed from the
/// adaptive ad size rather than hardcoded to 50pt.
struct MaybeBannerAd: View {
    @Environment(PurchaseStore.self) private var purchases
    var body: some View {
        if !purchases.isAdFree {
            let width = UIScreen.main.bounds.width
            BannerAdView(width: width)
                .frame(height: BannerAdView.adaptiveHeight(for: width))
                .background(.thinMaterial)
        }
    }
}

/// SwiftUI wrapper around `GADBannerView` for the anchored adaptive banner
/// at the bottom of the Browse and Map tabs.
///
/// Production ad unit for S-Tier Eats (registered standalone in AdMob,
/// distinct from the Fishing app's unit — AdMob server-side binds unit
/// IDs to the registered app's bundle ID at request time, so reuse across
/// bundle IDs returns no-fill):
///   ca-app-pub-1927040492403163/8897080292
///
/// v2.2: request personalization now follows ATT — `AdsService.adRequest()`
/// returns a personalized request when the user granted tracking, else the
/// non-personalized (NPA) request.
struct BannerAdView: UIViewRepresentable {
    let width: CGFloat
    let adUnitID: String

    init(width: CGFloat,
         adUnitID: String = "ca-app-pub-1927040492403163/8897080292") {
        self.width = width
        self.adUnitID = adUnitID
    }

    /// Height of the anchored adaptive banner for a given width — used to
    /// reserve the correct vertical space in MaybeBannerAd's frame.
    static func adaptiveHeight(for width: CGFloat) -> CGFloat {
        GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width).size.height
    }

    func makeUIView(context: Context) -> GADBannerView {
        let adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
        let banner = GADBannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(AdsService.shared.adRequest())
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
