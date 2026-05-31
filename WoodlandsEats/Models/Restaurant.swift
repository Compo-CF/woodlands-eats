import Foundation
import CoreLocation

struct Restaurant: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let area: Area
    let address: String
    let cuisines: [Cuisine]
    let priceTier: PriceTier
    let isFastFood: Bool
    let website: String?
    let phone: String?
    let description: String
    let signatureDishes: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    var primaryCuisine: Cuisine { cuisines.first ?? .other }

    var websiteURL: URL? { website.flatMap { URL(string: $0) } }

    var cuisineSummary: String {
        cuisines.map(\.displayName).joined(separator: " · ")
    }

    /// Memberwise init for building Restaurants from CloudKit LiveRestaurant
    /// records (the synthesized one is suppressed by the custom Decodable init).
    init(id: UUID, name: String, latitude: Double, longitude: Double, area: Area,
         address: String, cuisines: [Cuisine], priceTier: PriceTier, isFastFood: Bool,
         website: String?, phone: String?, description: String, signatureDishes: [String]) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.area = area; self.address = address; self.cuisines = cuisines; self.priceTier = priceTier
        self.isFastFood = isFastFood; self.website = website; self.phone = phone
        self.description = description; self.signatureDishes = signatureDishes
    }

    // signatureDishes is allowed to be absent in the JSON (defaults to []).
    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, area, address, cuisines,
             priceTier, isFastFood, website, phone, description, signatureDishes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        area = try c.decode(Area.self, forKey: .area)
        address = try c.decode(String.self, forKey: .address)
        cuisines = try c.decode([Cuisine].self, forKey: .cuisines)
        priceTier = try c.decode(PriceTier.self, forKey: .priceTier)
        isFastFood = try c.decodeIfPresent(Bool.self, forKey: .isFastFood) ?? false
        website = try c.decodeIfPresent(String.self, forKey: .website)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        description = try c.decode(String.self, forKey: .description)
        signatureDishes = try c.decodeIfPresent([String].self, forKey: .signatureDishes) ?? []
    }
}
