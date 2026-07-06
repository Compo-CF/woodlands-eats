import Foundation
import SwiftUI

/// The geographic sub-areas this app covers. Expanded in build 33 to
/// follow the polygon service area: original six (Woodlands core + Spring
/// + adjacent) plus Conroe to the north, Magnolia to the west, and
/// Atascocita to the east. New restaurants are auto-tagged to whichever
/// area centroid is closest by haversine distance (see scripts/retag_areas.py).
///
/// Lenient decode: rows with an unknown area string fall back to
/// `.woodlands` instead of failing the whole JSON parse — useful if a
/// future seed introduces a new area string before the enum is updated.
enum Area: String, Codable, CaseIterable, Identifiable {
    case woodlands, spring, shenandoah, oakRidgeNorth, oldTownSpring, klein,
         conroe, magnolia, atascocita, montgomery,
         // v1.8 southern/eastern expansion:
         tomball, cypress, champions, kingwood

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Area(rawValue: raw) ?? .woodlands
    }

    var displayName: String {
        switch self {
        case .woodlands: "The Woodlands"
        case .spring: "Spring"
        case .shenandoah: "Shenandoah"
        case .oakRidgeNorth: "Oak Ridge North"
        case .oldTownSpring: "Old Town Spring"
        case .klein: "Klein"
        case .conroe: "Conroe"
        case .magnolia: "Magnolia"
        case .atascocita: "Atascocita"
        case .montgomery: "Montgomery"
        case .tomball: "Tomball"
        case .cypress: "Cypress"
        case .champions: "Champions / FM 1960"
        case .kingwood: "Kingwood"
        }
    }
}

enum PriceTier: String, Codable, CaseIterable, Identifiable {
    case one = "$"
    case two = "$$"
    case three = "$$$"
    case four = "$$$$"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum Cuisine: String, Codable, CaseIterable, Identifiable {
    case american, southern, bbq, burgers, mexican, texMex, italian, pizza,
         seafood, steakhouse, sushi, japanese, chinese, thai, vietnamese,
         korean, indian, mediterranean, breakfastBrunch, cafeBakery,
         dessert, healthy, latin, french, other

    var id: String { rawValue }

    /// Lenient decode: an unrecognized cuisine string falls back to `.other`
    /// rather than failing the whole JSON parse.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Cuisine(rawValue: raw) ?? .other
    }

    var displayName: String {
        switch self {
        case .american: "American"
        case .southern: "Southern"
        case .bbq: "BBQ"
        case .burgers: "Burgers"
        case .mexican: "Mexican"
        case .texMex: "Tex-Mex"
        case .italian: "Italian"
        case .pizza: "Pizza"
        case .seafood: "Seafood"
        case .steakhouse: "Steakhouse"
        case .sushi: "Sushi"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        case .thai: "Thai"
        case .vietnamese: "Vietnamese"
        case .korean: "Korean"
        case .indian: "Indian"
        case .mediterranean: "Mediterranean"
        case .breakfastBrunch: "Breakfast & Brunch"
        case .cafeBakery: "Café & Bakery"
        case .dessert: "Dessert"
        case .healthy: "Healthy"
        case .latin: "Latin"
        case .french: "French"
        case .other: "Other"
        }
    }
}

/// The crowdsourced ranking primitive: an S/A/B/C/F tier list.
/// No star ratings — you place each spot in a tier, and (Phase 1) the
/// community average surfaces a consensus tier per restaurant.
enum Tier: String, Codable, CaseIterable, Identifiable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case f = "F"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Numeric weight used to average personal lists into a community tier.
    var score: Int {
        switch self {
        case .s: 5
        case .a: 4
        case .b: 3
        case .c: 2
        case .f: 1
        }
    }

    var color: Color {
        switch self {
        case .s: Color(red: 0.90, green: 0.22, blue: 0.27)
        case .a: Color(red: 0.96, green: 0.55, blue: 0.20)
        case .b: Color(red: 0.95, green: 0.78, blue: 0.24)
        case .c: Color(red: 0.40, green: 0.73, blue: 0.42)
        case .f: Color(red: 0.55, green: 0.35, blue: 0.78)
        }
    }

    var blurb: String {
        switch self {
        case .s: "Elite — always worth it"
        case .a: "Great — go often"
        case .b: "Solid — happy to return"
        case .c: "Fine — in a pinch"
        case .f: "Skip it"
        }
    }

    /// Maps an averaged score (1...5) back to the nearest tier, for the
    /// community consensus letter.
    static func from(averageScore: Double) -> Tier {
        switch averageScore {
        case 4.5...: .s
        case 3.5..<4.5: .a
        case 2.5..<3.5: .b
        case 1.5..<2.5: .c
        default: .f
        }
    }
}
