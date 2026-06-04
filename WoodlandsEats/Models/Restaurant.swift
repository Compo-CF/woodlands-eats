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
    /// Google Places `reservable` boolean. `nil` when unenriched (treat as false).
    /// Drives whether the "Reserve" action button is shown.
    let reservable: Bool?
    /// Google Places `delivery` boolean. `nil` when unenriched.
    let delivery: Bool?
    /// Google Places `takeout` boolean. `nil` when unenriched.
    let takeout: Bool?
    /// Google Places `dineIn` boolean. `nil` when unenriched.
    let dineIn: Bool?

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
         website: String?, phone: String?, description: String, signatureDishes: [String],
         reservable: Bool? = nil, delivery: Bool? = nil, takeout: Bool? = nil, dineIn: Bool? = nil) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.area = area; self.address = address; self.cuisines = cuisines; self.priceTier = priceTier
        self.isFastFood = isFastFood; self.website = website; self.phone = phone
        self.description = description; self.signatureDishes = signatureDishes
        self.reservable = reservable; self.delivery = delivery
        self.takeout = takeout; self.dineIn = dineIn
    }

    // signatureDishes is allowed to be absent in the JSON (defaults to []).
    // reservable/delivery/takeout/dineIn are absent on pre-v1.1 seed rows;
    // decodeIfPresent leaves them as nil, which the view layer treats as false.
    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, area, address, cuisines,
             priceTier, isFastFood, website, phone, description, signatureDishes,
             reservable, delivery, takeout, dineIn
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
        reservable = try c.decodeIfPresent(Bool.self, forKey: .reservable)
        delivery = try c.decodeIfPresent(Bool.self, forKey: .delivery)
        takeout = try c.decodeIfPresent(Bool.self, forKey: .takeout)
        dineIn = try c.decodeIfPresent(Bool.self, forKey: .dineIn)
    }
}
