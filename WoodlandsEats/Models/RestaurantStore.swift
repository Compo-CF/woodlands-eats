import Foundation
import CoreLocation
import Observation

@Observable
final class RestaurantStore {
    /// What views read — the bundled/remote seed PLUS any live admin-approved
    /// additions fetched from CloudKit.
    var restaurants: [Restaurant] = []
    /// Bundled (or remote-cached) seed, kept separately so refreshing live
    /// additions doesn't lose it.
    private var seedRestaurants: [Restaurant] = []
    /// Admin-approved community submissions fetched from CloudKit at launch.
    private(set) var liveRestaurants: [Restaurant] = []
    var filter = RestaurantFilter()
    var userLocation: CLLocation?
    /// v1.5: restaurants the admin has confirmed as permanently closed.
    /// `filteredRestaurants` drops these so Map + Browse + sort variants
    /// hide them from discovery surfaces. Synced from
    /// `CloudKitService.confirmedClosedIDs` by the view layer after each
    /// closure-related CloudKit refresh (launch + admin decisions).
    /// Not used by My Tiers — that surface reads `restaurants` directly
    /// so the user's personal ranking history stays intact even when a
    /// place closes.
    var confirmedClosedIDs: Set<UUID> = []

    /// Remote source of truth. Edit `docs/Restaurants.json` in the repo, push to
    /// main, and GitHub Pages serves the update — every app picks it up on next
    /// launch. No app release needed for data-only changes (new spots, fixed
    /// coords). Until Pages is set up this 404s harmlessly and we fall back to
    /// the bundled seed.
    private let remoteURL = URL(string: "https://compo-cf.github.io/woodlands-eats/Restaurants.json")!

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("Restaurants.cache.json")
    }

    init() {
        loadLocalFirst()
        Task { await refreshFromRemote() }
    }

    private func loadLocalFirst() {
        if let cached = try? Data(contentsOf: cacheURL), let decoded = Self.decode(cached) {
            seedRestaurants = decoded
            merge()
            return
        }
        loadBundled()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "Restaurants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = Self.decode(data) else {
            print("Bundled Restaurants.json missing or invalid")
            return
        }
        seedRestaurants = decoded
        merge()
    }

    private func merge() {
        restaurants = seedRestaurants + liveRestaurants
    }

    /// Pull admin-approved community additions from CloudKit and merge them in.
    @MainActor
    func refreshLive(via cloudKit: CloudKitService) async {
        liveRestaurants = await cloudKit.fetchLiveRestaurants()
        merge()
    }

    @MainActor
    func refreshFromRemote() async {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let decoded = Self.decode(data),
                  !decoded.isEmpty
            else { return }
            seedRestaurants = decoded
            merge()
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            // Offline or fetch failed — keep the local data from loadLocalFirst().
        }
    }

    private static func decode(_ data: Data) -> [Restaurant]? {
        try? JSONDecoder().decode(RestaurantsFile.self, from: data).restaurants
    }

    var filteredRestaurants: [Restaurant] {
        restaurants.filter { r in
            // v1.5: drop admin-confirmed-closed spots from discovery
            // surfaces. They stay in `restaurants` so My Tiers + the
            // Detail page (reachable via deep link or My Tiers) keep
            // showing them — this is just the public-discovery filter.
            if confirmedClosedIDs.contains(r.id) { return false }
            if !filter.includeFastFood && r.isFastFood { return false }
            if !filter.selectedAreas.isEmpty && !filter.selectedAreas.contains(r.area) {
                return false
            }
            if !filter.selectedCuisines.isEmpty &&
                filter.selectedCuisines.isDisjoint(with: Set(r.cuisines)) {
                return false
            }
            if !filter.selectedPrices.isEmpty && !filter.selectedPrices.contains(r.priceTier) {
                return false
            }
            if !filter.searchText.isEmpty {
                let q = filter.searchText
                let matchesName = r.name.localizedCaseInsensitiveContains(q)
                let matchesCuisine = r.cuisines.contains {
                    $0.displayName.localizedCaseInsensitiveContains(q)
                }
                if !matchesName && !matchesCuisine { return false }
            }
            return true
        }
    }

    var restaurantsSortedByDistance: [Restaurant] {
        guard let userLocation else { return filteredRestaurants }
        return filteredRestaurants.sorted {
            $0.distance(from: userLocation) < $1.distance(from: userLocation)
        }
    }

    var restaurantsSortedByName: [Restaurant] {
        filteredRestaurants.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

struct RestaurantFilter {
    var searchText: String = ""
    var selectedAreas: Set<Area> = []
    var selectedCuisines: Set<Cuisine> = []
    var selectedPrices: Set<PriceTier> = []
    /// Commodity fast food is hidden by default; users opt it in.
    var includeFastFood: Bool = false
    /// Build 28: limit results to restaurants the user has placed in a tier.
    /// The flag lives here for UI consistency (FilterBar binds to it) but the
    /// actual ranked-membership check happens at the view layer, because
    /// only the views have access to TierListStore.
    var rankedOnly: Bool = false

    var isActive: Bool {
        !searchText.isEmpty || !selectedAreas.isEmpty ||
        !selectedCuisines.isEmpty || !selectedPrices.isEmpty ||
        includeFastFood || rankedOnly
    }

    mutating func clear() {
        searchText = ""
        selectedAreas = []
        selectedCuisines = []
        selectedPrices = []
        includeFastFood = false
        rankedOnly = false
    }
}

private struct RestaurantsFile: Codable {
    let restaurants: [Restaurant]
}
