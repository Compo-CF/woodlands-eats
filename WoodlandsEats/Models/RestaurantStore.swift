import Foundation
import CoreLocation
import Observation

@Observable
final class RestaurantStore {
    var restaurants: [Restaurant] = []
    var filter = RestaurantFilter()
    var userLocation: CLLocation?

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
            restaurants = decoded
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
        restaurants = decoded
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
            restaurants = decoded
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

    var isActive: Bool {
        !searchText.isEmpty || !selectedAreas.isEmpty ||
        !selectedCuisines.isEmpty || !selectedPrices.isEmpty
    }

    mutating func clear() {
        searchText = ""
        selectedAreas = []
        selectedCuisines = []
        selectedPrices = []
    }
}

private struct RestaurantsFile: Codable {
    let restaurants: [Restaurant]
}
