import Foundation

/// v3.1.1: "Date Night Tiers" — a limited-time Valentine community board, run as an
/// App Store In-App Event (Jan 28 – Feb 15 2027, Central time).
///
/// While live, the Community tab shows a banner that opens the board. The board ranks
/// date-night spots by live community consensus. Outside the window the banner is gone;
/// `stier://datenight` still opens the board so the event card never lands on a dead screen.
enum DateNight2027 {
    static let deepLink = "stier://datenight"

    private static let central = TimeZone(identifier: "America/Chicago")!

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = central
        return cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    /// Jan 28 2027 00:00 CT.
    static let start = date(2027, 1, 28)
    /// Feb 16 2027 00:00 CT — the board runs through Feb 15.
    static let end = date(2027, 2, 16)

    enum Phase { case upcoming, live, ended }

    static func phase(at now: Date = Date()) -> Phase {
        if now < start { return .upcoming }
        if now < end { return .live }
        return .ended
    }

    static var isLive: Bool { phase() == .live }

    static func daysLeft(at now: Date = Date()) -> Int {
        max(1, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    static func matches(_ url: URL) -> Bool {
        url.scheme == "stier" && (url.host ?? "").lowercased() == "datenight"
    }

    /// Classic date-night cuisines.
    static let dateCuisines: Set<Cuisine> = [.steakhouse, .seafood, .italian, .french, .sushi, .japanese, .mediterranean]

    /// A date-night spot: sit-down (not fast food) and either takes reservations,
    /// is upscale ($$$ or $$$$), or serves a classic date cuisine.
    static func isDateSpot(_ r: Restaurant) -> Bool {
        guard !r.isFastFood else { return false }
        if r.reservable == true { return true }
        if r.priceTier == .three || r.priceTier == .four { return true }
        return !dateCuisines.isDisjoint(with: r.cuisines)
    }

    /// "Vibe" categories shown as champions (title, filter).
    static let vibes: [(title: String, test: (Restaurant) -> Bool)] = [
        ("Book ahead", { $0.reservable == true }),
        ("Splurge ($$$+)", { $0.priceTier == .three || $0.priceTier == .four }),
        ("Steak & seafood", { !Set($0.cuisines).isDisjoint(with: [.steakhouse, .seafood]) }),
        ("Italian", { $0.cuisines.contains(.italian) }),
        ("French", { $0.cuisines.contains(.french) }),
        ("Sushi & Japanese", { !Set($0.cuisines).isDisjoint(with: [.sushi, .japanese]) }),
        ("Mediterranean", { $0.cuisines.contains(.mediterranean) }),
    ]

    static let minVotesTop = 3
    static let minVotesVibe = 2
}
