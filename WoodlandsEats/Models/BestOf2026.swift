import Foundation

/// v3.1.1: "Best of 2026" — a limited-time year-end community board, run as an
/// App Store In-App Event (Dec 10 2026 – Jan 5 2027, Central time).
///
/// While the event is live the Community tab shows a banner that opens the
/// board, and every tier placement made in the window feeds it (the board reads
/// the same live consensus docs as Community). Outside the window the banner is
/// gone; the deep link `stier://bestof2026` still opens the board (with a
/// "starts Dec 10" / "final standings" header) so the App Store event card never
/// lands on a dead screen.
enum BestOf2026 {
    /// Deep link the App Store event card opens.
    static let deepLink = "stier://bestof2026"

    private static let central = TimeZone(identifier: "America/Chicago")!

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = central
        return cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    /// First moment of the event (Dec 10 2026, 00:00 CT).
    static let start = date(2026, 12, 10)
    /// First moment AFTER the event (Jan 6 2027, 00:00 CT) — the board runs through Jan 5.
    static let end = date(2027, 1, 6)

    enum Phase { case upcoming, live, ended }

    static func phase(at now: Date = Date()) -> Phase {
        if now < start { return .upcoming }
        if now < end { return .live }
        return .ended
    }

    static var isLive: Bool { phase() == .live }

    /// Whole days left in the event (1 on the last day).
    static func daysLeft(at now: Date = Date()) -> Int {
        let secs = end.timeIntervalSince(now)
        return max(1, Int((secs / 86_400).rounded(.up)))
    }

    /// True for a URL that should open the board.
    static func matches(_ url: URL) -> Bool {
        guard url.scheme == "stier" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "bestof2026" || host == "bestof"
    }

    /// Cuisines eligible for a "category champion", in display priority order.
    static let categories: [Cuisine] = [
        .bbq, .texMex, .mexican, .burgers, .pizza, .sushi, .italian,
        .breakfastBrunch, .seafood, .steakhouse, .southern, .american,
        .cafeBakery, .dessert, .thai, .vietnamese, .chinese, .japanese,
        .korean, .indian, .mediterranean, .latin, .french, .healthy,
    ]

    /// Minimum votes for the overall Top 10 and for a category champion.
    static let minVotesTop = 3
    static let minVotesCategory = 2
}
