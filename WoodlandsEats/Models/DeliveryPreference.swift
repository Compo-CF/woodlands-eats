import Foundation

/// Persisted choice of delivery app (DoorDash vs Uber Eats).
///
/// v1.2 action-row "Order" button: first tap shows a picker sheet, subsequent
/// taps deeplink directly into the saved app's search results. Profile has a
/// "Reset delivery preference" affordance for changing it later.
///
/// Both apps' search URLs are public Universal Links that open the native app
/// when installed, fall back to the mobile web page when not. No affiliate
/// approval is required — affiliate tracking params would be appended later
/// once Impact.com applications go through.
enum DeliveryApp: String, CaseIterable, Identifiable {
    case doordash
    case ubereats

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .doordash:  return "DoorDash"
        case .ubereats:  return "Uber Eats"
        }
    }

    var systemImage: String {
        // SF Symbols doesn't ship brand logos; use a generic bag icon.
        // If we add asset-catalog logos later, swap this for `Image("doordash")`.
        switch self {
        case .doordash:  return "bag.fill"
        case .ubereats:  return "bag.fill"
        }
    }

    /// Universal Link to the app's search results for the given restaurant.
    /// On a device with the app installed iOS routes this to the native app;
    /// otherwise it opens the mobile web page.
    func searchURL(for restaurantName: String, city: String) -> URL {
        let q = "\(restaurantName) \(city)"
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch self {
        case .doordash:
            return URL(string: "https://www.doordash.com/search/store/\(encoded)")!
        case .ubereats:
            return URL(string: "https://www.ubereats.com/search?q=\(encoded)")!
        }
    }
}

/// Tiny UserDefaults wrapper. Not @Observable on purpose — the value flips
/// at most once per user lifetime in practice, and the read sites all happen
/// in response to user taps (no view-state reactivity needed).
enum DeliveryPreference {
    private static let key = "STierEats.preferredDeliveryApp"

    static var current: DeliveryApp? {
        UserDefaults.standard.string(forKey: key).flatMap(DeliveryApp.init(rawValue:))
    }

    static func set(_ app: DeliveryApp) {
        UserDefaults.standard.set(app.rawValue, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
