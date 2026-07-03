import Foundation

/// v1.8 (integrity audit): pure-analysis engine that inspects the full
/// CloudKit Placement corpus for patterns consistent with gaming —
/// astroturfing (owners inflating own ratings), vendetta accounts
/// torching competitors, sock-puppet clusters, coordinated bursts.
///
/// Fetches happen in CloudKitService.fetchAllPlacementsForAudit; this
/// module takes the raw records and produces a ranked list of AuditSignal
/// findings for the admin to eyeball.
///
/// IMPORTANT: These are heuristics, not proof. A finding here means
/// "worth a look" — the admin decides whether to ignore, warn, or
/// revoke placements. Apple hides Apple-ID-level identity so we cannot
/// prove two accounts are the same person; we can only surface
/// suspicious patterns.

/// One Placement pulled straight from CloudKit with the fields we need
/// for auditing (owner, restaurant, tier, when).
struct AuditPlacement {
    let userID: String              // CloudKit userRecordName (opaque, stable per iCloud account)
    let restaurantID: UUID
    let tier: Tier
    let creationDate: Date
}

/// A flagged pattern the admin should review.
struct AuditSignal: Identifiable {
    let id = UUID()
    let severity: Severity
    let category: Category
    let title: String
    let detail: String
    /// Optional userID at the center of the finding (for user-focused
    /// signals) so the UI can jump to that user's placement list.
    let userID: String?
    /// Optional restaurantID for restaurant-focused signals.
    let restaurantID: UUID?

    enum Severity: Int, Comparable {
        case low = 0, medium = 1, high = 2
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        var displayName: String {
            switch self { case .low: "Low"; case .medium: "Medium"; case .high: "High" }
        }
    }

    enum Category {
        case biasedUser        // user's distribution wildly skewed toward S or F
        case microExtremeUser  // <= 3 placements, all extreme, one target
        case polarizedRestaurant  // bimodal S/F, little middle
        case coordinatedBurst  // N placements same tier same restaurant, tight window
        case concentrationRisk // consensus swings if one user's vote is removed
        var displayName: String {
            switch self {
            case .biasedUser: "Biased user"
            case .microExtremeUser: "Micro-extreme user"
            case .polarizedRestaurant: "Polarized restaurant"
            case .coordinatedBurst: "Coordinated burst"
            case .concentrationRisk: "Concentration risk"
            }
        }
        var systemImage: String {
            switch self {
            case .biasedUser: "person.crop.circle.badge.exclamationmark"
            case .microExtremeUser: "person.crop.circle.badge.questionmark"
            case .polarizedRestaurant: "chart.bar.fill"
            case .coordinatedBurst: "bolt.horizontal.fill"
            case .concentrationRisk: "scalemass"
            }
        }
    }
}

/// Analysis output — signals + a summary line.
struct AuditReport {
    let signals: [AuditSignal]
    let totalUsers: Int
    let totalPlacements: Int
    let totalRestaurantsRanked: Int
    let generatedAt: Date
}

@Observable
final class AuditService {
    /// Placeholder — the service is stateless. Kept as a struct-like class
    /// so it can be @Environment-injected and testable if needed later.

    // ─── Threshold constants ─────────────────────────────────────────
    /// Ignore users with fewer placements than this for the biased-user
    /// signal — too few data points to reliably flag as skewed.
    private let biasedUserMinPlacements = 5
    /// Skew threshold: X% or more of a user's placements at the same
    /// extreme tier (S or F). 80% = medium; 95% = high.
    private let biasedUserThresholdMedium = 0.80
    private let biasedUserThresholdHigh = 0.95

    /// Micro-extreme: 1-3 placements, all at S or all at F, plus
    /// targeting <=2 different restaurants.
    private let microExtremeMaxPlacements = 3

    /// Restaurant polarization: >=5 total votes, and >=75% at extremes
    /// (S + F) with at least 2 each side. The bulge-at-both-ends shape.
    private let polarizedMinTotal = 5
    private let polarizedThreshold = 0.75

    /// Coordinated burst: N placements of same tier for same restaurant
    /// within window seconds.
    private let burstMinCount = 3
    private let burstWindowSeconds: TimeInterval = 6 * 3600  // 6 hours

    // ─── Public API ──────────────────────────────────────────────────

    /// Run every check over the corpus and return the ranked report.
    /// High severity first; ties broken by category.
    func analyze(_ placements: [AuditPlacement]) -> AuditReport {
        var signals: [AuditSignal] = []
        signals.append(contentsOf: findBiasedUsers(placements))
        signals.append(contentsOf: findMicroExtremeUsers(placements))
        signals.append(contentsOf: findPolarizedRestaurants(placements))
        signals.append(contentsOf: findCoordinatedBursts(placements))
        signals.append(contentsOf: findConcentrationRisks(placements))
        signals.sort { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            return a.title < b.title
        }
        let users = Set(placements.map(\.userID))
        let restaurants = Set(placements.map(\.restaurantID))
        return AuditReport(
            signals: signals,
            totalUsers: users.count,
            totalPlacements: placements.count,
            totalRestaurantsRanked: restaurants.count,
            generatedAt: Date()
        )
    }

    // ─── Individual detectors ────────────────────────────────────────

    /// Users whose placement distribution is dominated by one extreme
    /// tier (S or F). Very common gaming pattern: rate my thing S,
    /// rate competitors F, ignore everything else.
    private func findBiasedUsers(_ placements: [AuditPlacement]) -> [AuditSignal] {
        let byUser = Dictionary(grouping: placements, by: \.userID)
        var out: [AuditSignal] = []
        for (userID, userPlacements) in byUser {
            let total = userPlacements.count
            guard total >= biasedUserMinPlacements else { continue }
            let sCount = userPlacements.filter { $0.tier == .s }.count
            let fCount = userPlacements.filter { $0.tier == .f }.count
            let sFrac = Double(sCount) / Double(total)
            let fFrac = Double(fCount) / Double(total)
            let (extremeTier, extremeFrac) = sFrac >= fFrac ? ("S", sFrac) : ("F", fFrac)
            guard extremeFrac >= biasedUserThresholdMedium else { continue }
            let severity: AuditSignal.Severity =
                extremeFrac >= biasedUserThresholdHigh ? .high : .medium
            out.append(AuditSignal(
                severity: severity,
                category: .biasedUser,
                title: "User heavily biased to \(extremeTier)-tier",
                detail: "\(Int(extremeFrac * 100))% of this user's \(total) placements are \(extremeTier). Distribution: S=\(sCount) A=\(userPlacements.filter{$0.tier == .a}.count) B=\(userPlacements.filter{$0.tier == .b}.count) C=\(userPlacements.filter{$0.tier == .c}.count) F=\(fCount).",
                userID: userID,
                restaurantID: nil
            ))
        }
        return out
    }

    /// New / low-engagement accounts whose only activity is extreme
    /// ratings on 1-2 targets. Classic astroturf shape: signed in
    /// once, rated the target, never came back.
    private func findMicroExtremeUsers(_ placements: [AuditPlacement]) -> [AuditSignal] {
        let byUser = Dictionary(grouping: placements, by: \.userID)
        var out: [AuditSignal] = []
        for (userID, userPlacements) in byUser {
            let total = userPlacements.count
            guard total >= 1, total <= microExtremeMaxPlacements else { continue }
            // All placements at same extreme tier?
            let tiers = Set(userPlacements.map(\.tier))
            guard tiers.count == 1, let onlyTier = tiers.first,
                  onlyTier == .s || onlyTier == .f else { continue }
            // Targeting a small set of restaurants (usually 1)
            let targets = Set(userPlacements.map(\.restaurantID))
            guard targets.count <= 2 else { continue }
            let severity: AuditSignal.Severity =
                total == 1 ? .low : .medium
            let targetList = targets.map { $0.uuidString }.sorted().joined(separator: ", ")
            out.append(AuditSignal(
                severity: severity,
                category: .microExtremeUser,
                title: "Sole activity: \(total) \(onlyTier.label)-tier placement\(total == 1 ? "" : "s")",
                detail: "This account has only \(total) total placement\(total == 1 ? "" : "s"), all \(onlyTier.label)-tier, targeting \(targets.count) restaurant\(targets.count == 1 ? "" : "s"). Restaurant IDs: \(targetList)",
                userID: userID,
                restaurantID: targets.count == 1 ? targets.first : nil
            ))
        }
        return out
    }

    /// Restaurants where the vote distribution is bimodal — lots of S
    /// AND lots of F, few middle tiers. Could indicate genuine
    /// controversy (people either love or hate the food) OR gaming
    /// (owner supporters vs. competitor detractors). Admin decides.
    private func findPolarizedRestaurants(_ placements: [AuditPlacement]) -> [AuditSignal] {
        let byRestaurant = Dictionary(grouping: placements, by: \.restaurantID)
        var out: [AuditSignal] = []
        for (rid, rPlacements) in byRestaurant {
            let total = rPlacements.count
            guard total >= polarizedMinTotal else { continue }
            let sCount = rPlacements.filter { $0.tier == .s }.count
            let fCount = rPlacements.filter { $0.tier == .f }.count
            let extremeFrac = Double(sCount + fCount) / Double(total)
            guard extremeFrac >= polarizedThreshold, sCount >= 2, fCount >= 2 else { continue }
            out.append(AuditSignal(
                severity: .medium,
                category: .polarizedRestaurant,
                title: "Restaurant with bimodal ratings",
                detail: "\(total) placements: S=\(sCount) F=\(fCount) middle=\(total - sCount - fCount). \(Int(extremeFrac*100))% at extremes.",
                userID: nil,
                restaurantID: rid
            ))
        }
        return out
    }

    /// Same restaurant, same tier, N+ placements within a tight time
    /// window. Coordinated review-bombing (or love-bombing) pattern.
    private func findCoordinatedBursts(_ placements: [AuditPlacement]) -> [AuditSignal] {
        let byRestaurantTier = Dictionary(grouping: placements) { p in
            "\(p.restaurantID.uuidString)_\(p.tier.rawValue)"
        }
        var out: [AuditSignal] = []
        for (_, group) in byRestaurantTier {
            guard group.count >= burstMinCount else { continue }
            let sorted = group.sorted { $0.creationDate < $1.creationDate }
            // Sliding window: find any span of burstMinCount consecutive
            // placements whose first-to-last delta is <= burstWindowSeconds.
            for i in 0...(sorted.count - burstMinCount) {
                let last = i + burstMinCount - 1
                let span = sorted[last].creationDate.timeIntervalSince(sorted[i].creationDate)
                guard span <= burstWindowSeconds else { continue }
                let tier = sorted[i].tier
                let rid = sorted[i].restaurantID
                let hours = span / 3600
                out.append(AuditSignal(
                    severity: burstMinCount >= 5 ? .high : .medium,
                    category: .coordinatedBurst,
                    title: "\(burstMinCount) \(tier.label)-tier placements in \(String(format: "%.1f", hours))h",
                    detail: "Same restaurant received \(burstMinCount)+ placements all at \(tier.label)-tier within a \(String(format: "%.1f", hours))-hour window. First: \(sorted[i].creationDate), last: \(sorted[last].creationDate).",
                    userID: nil,
                    restaurantID: rid
                ))
                break   // Only flag the tightest burst per (restaurant, tier) group.
            }
        }
        return out
    }

    /// Restaurants whose consensus tier depends on a single user's vote.
    /// Fragile — one bad-actor swing changes the shown consensus.
    /// Informational (low severity) unless combined with other flags.
    private func findConcentrationRisks(_ placements: [AuditPlacement]) -> [AuditSignal] {
        let byRestaurant = Dictionary(grouping: placements, by: \.restaurantID)
        var out: [AuditSignal] = []
        for (rid, rPlacements) in byRestaurant {
            // Need >=3 votes to be flaggable — 2-vote restaurants are
            // trivially fragile and not interesting to flag.
            guard rPlacements.count >= 3 else { continue }
            let currentAvg = averageScore(rPlacements)
            let currentTier = tierFromAverage(currentAvg)
            // Try removing each user's vote once. If ANY removal changes
            // the derived tier, it's concentration-risk.
            var vulnerable = false
            var pivotalUser: String?
            for i in 0..<rPlacements.count {
                var copy = rPlacements
                let removed = copy.remove(at: i)
                let newAvg = averageScore(copy)
                let newTier = tierFromAverage(newAvg)
                if newTier != currentTier {
                    vulnerable = true
                    pivotalUser = removed.userID
                    break
                }
            }
            guard vulnerable else { continue }
            out.append(AuditSignal(
                severity: .low,
                category: .concentrationRisk,
                title: "Consensus swings on one vote",
                detail: "This restaurant's consensus tier (\(currentTier.label)) changes if any single user's placement is removed. Current: \(rPlacements.count) votes.",
                userID: pivotalUser,
                restaurantID: rid
            ))
        }
        return out
    }

    // ─── Helpers ─────────────────────────────────────────────────────
    private func averageScore(_ placements: [AuditPlacement]) -> Double {
        guard !placements.isEmpty else { return 0 }
        let total = placements.map { Double($0.tier.score) }.reduce(0, +)
        return total / Double(placements.count)
    }

    private func tierFromAverage(_ avg: Double) -> Tier {
        // Same thresholds the Community board uses — 4.5+ = S, 3.5+ = A, etc.
        switch avg {
        case 4.5...: return .s
        case 3.5...: return .a
        case 2.5...: return .b
        case 1.5...: return .c
        default: return .f
        }
    }
}
