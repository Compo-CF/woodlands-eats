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

    // signatureDishes is allowed to be absent in the JSON (defaults to []).
    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, area, address, cuisines,
             priceTier, website, phone, description, signatureDishes
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
        website = try c.decodeIfPresent(String.self, forKey: .website)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        description = try c.decode(String.self, forKey: .description)
        signatureDishes = try c.decodeIfPresent([String].self, forKey: .signatureDishes) ?? []
    }
}
