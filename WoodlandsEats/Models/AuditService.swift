import Foundation

/// v1.8 (integrity audit): entity-centric analysis over the full CloudKit
/// Placement corpus. Answers two admin questions directly:
///   1. WHICH USERS should I check?     → ranked [UserAudit]
///   2. WHICH RESTAURANTS should I check? → ranked [RestaurantAudit]
///
/// Each entity carries a suspicion score, the plain-English reasons it
/// was flagged, and the full evidence (every placement involved) so the
/// admin can eyeball and then remediate (ban user / exclude rating)
/// straight from the audit screen.
///
/// These are heuristics, not proof — Apple hides Apple-ID-level identity,
/// so two iCloud accounts can't be linked to one person. Scores rank
/// "worth a look," the admin decides.

/// One Placement pulled from CloudKit with audit-relevant metadata.
/// `recordName` is carried so individual ratings can be excluded via an
/// admin-owned AdminExclusion record (we can't delete another user's
/// record in the public DB — only mask it).
struct AuditPlacement: Identifiable {
    let recordName: String          // "placement_<userID>_<restaurantUUID>"
    let userID: String              // CloudKit userRecordName (opaque, stable per iCloud account)
    let restaurantID: UUID
    let tier: Tier
    let creationDate: Date
    var id: String { recordName }
}

/// A user flagged for review, with score, reasons, and full history.
struct UserAudit: Identifiable {
    let userID: String
    /// Every placement this user has made, newest first.
    let placements: [AuditPlacement]
    let score: Int
    let reasons: [String]
    var id: String { userID }

    var tierCounts: [Tier: Int] {
        Dictionary(grouping: placements, by: \.tier).mapValues(\.count)
    }
    var distributionString: String {
        Tier.allCases
            .compactMap { t in (tierCounts[t] ?? 0) > 0 ? "\(t.label):\(tierCounts[t]!)" : nil }
            .joined(separator: "  ")
    }
}

/// A restaurant flagged for review, with score, reasons, and every vote.
struct RestaurantAudit: Identifiable {
    let restaurantID: UUID
    /// Every vote on this restaurant, newest first.
    let votes: [AuditPlacement]
    let score: Int
    let reasons: [String]
    var id: UUID { restaurantID }

    var tierCounts: [Tier: Int] {
        Dictionary(grouping: votes, by: \.tier).mapValues(\.count)
    }
    var distributionString: String {
        Tier.allCases
            .compactMap { t in (tierCounts[t] ?? 0) > 0 ? "\(t.label):\(tierCounts[t]!)" : nil }
            .joined(separator: "  ")
    }
}

struct AuditReport {
    /// Users with score > 0, highest first.
    let suspiciousUsers: [UserAudit]
    /// Restaurants with score > 0, highest first.
    let suspiciousRestaurants: [RestaurantAudit]
    let totalUsers: Int
    let totalPlacements: Int
    let totalRestaurantsRanked: Int
    let generatedAt: Date
}

final class AuditService {

    // ─── Thresholds ──────────────────────────────────────────────────
    private let biasedMinPlacements = 5
    private let biasedMedium = 0.80       // 80%+ at one extreme → +25
    private let biasedHigh = 0.95         // 95%+ → +40
    private let microExtremeMax = 3       // 1-3 placements, all one extreme
    private let polarizedMinVotes = 5
    private let polarizedFrac = 0.75      // 75%+ of votes at S+F, ≥2 each side
    private let burstCount = 3            // same tier, same restaurant…
    private let burstWindow: TimeInterval = 6 * 3600   // …within 6 hours

    /// Score weights. Roughly: 40+ = look today, 20-39 = look this week,
    /// under 20 = informational.
    private enum Points {
        static let biasedHigh = 40
        static let biasedMedium = 25
        static let microExtremeMulti = 30   // 2-3 placements, all extreme, ≤2 targets
        static let microExtremeSingle = 10  // single extreme placement (weak alone)
        static let inBurst = 15             // user participated in a burst
        static let polarized = 25
        static let burstRestaurant = 30
        static let burstRestaurantBig = 45  // 5+ in window
        static let suspiciousVoter = 15     // per flagged user voting extreme on this restaurant
        static let concentration = 10
    }

    func analyze(_ placements: [AuditPlacement]) -> AuditReport {
        let byUser = Dictionary(grouping: placements, by: \.userID)
        let byRestaurant = Dictionary(grouping: placements, by: \.restaurantID)

        // ─── Pass 1: user-level flags ────────────────────────────────
        var userScores: [String: Int] = [:]
        var userReasons: [String: [String]] = [:]

        for (uid, ps) in byUser {
            let total = ps.count
            let s = ps.filter { $0.tier == .s }.count
            let f = ps.filter { $0.tier == .f }.count

            // Biased distribution (needs enough data points)
            if total >= biasedMinPlacements {
                let (label, frac) = s >= f
                    ? ("S", Double(s) / Double(total))
                    : ("F", Double(f) / Double(total))
                if frac >= biasedHigh {
                    userScores[uid, default: 0] += Points.biasedHigh
                    userReasons[uid, default: []].append(
                        "\(Int(frac * 100))% of their \(total) placements are \(label)-tier")
                } else if frac >= biasedMedium {
                    userScores[uid, default: 0] += Points.biasedMedium
                    userReasons[uid, default: []].append(
                        "\(Int(frac * 100))% of their \(total) placements are \(label)-tier")
                }
            }

            // Micro-extreme account (signup-and-torch / signup-and-pump)
            if total >= 1, total <= microExtremeMax {
                let tiers = Set(ps.map(\.tier))
                let targets = Set(ps.map(\.restaurantID))
                if tiers.count == 1, let only = tiers.first,
                   (only == .s || only == .f), targets.count <= 2 {
                    if total >= 2 {
                        userScores[uid, default: 0] += Points.microExtremeMulti
                        userReasons[uid, default: []].append(
                            "Account's only activity: \(total) \(only.label)-tier votes on \(targets.count) restaurant\(targets.count == 1 ? "" : "s")")
                    } else {
                        userScores[uid, default: 0] += Points.microExtremeSingle
                        userReasons[uid, default: []].append(
                            "Single-purpose account: one \(only.label)-tier vote and nothing else")
                    }
                }
            }
        }

        // ─── Pass 2: restaurant-level flags ──────────────────────────
        var restScores: [UUID: Int] = [:]
        var restReasons: [UUID: [String]] = [:]

        for (rid, votes) in byRestaurant {
            let total = votes.count
            let s = votes.filter { $0.tier == .s }.count
            let f = votes.filter { $0.tier == .f }.count

            // Polarized (bimodal) distribution
            if total >= polarizedMinVotes, s >= 2, f >= 2,
               Double(s + f) / Double(total) >= polarizedFrac {
                restScores[rid, default: 0] += Points.polarized
                restReasons[rid, default: []].append(
                    "Bimodal votes: S=\(s) F=\(f) middle=\(total - s - f) — love-it/hate-it split")
            }

            // Coordinated burst: same tier, N+ votes, tight window.
            // Also credits the participating users (+inBurst each).
            for tier in [Tier.s, Tier.f] {
                let group = votes.filter { $0.tier == tier }
                    .sorted { $0.creationDate < $1.creationDate }
                guard group.count >= burstCount else { continue }
                for i in 0...(group.count - burstCount) {
                    let windowSlice = group[i...].prefix(while: {
                        $0.creationDate.timeIntervalSince(group[i].creationDate) <= burstWindow
                    })
                    guard windowSlice.count >= burstCount else { continue }
                    let n = windowSlice.count
                    let hours = windowSlice.last!.creationDate
                        .timeIntervalSince(windowSlice.first!.creationDate) / 3600
                    restScores[rid, default: 0] +=
                        n >= 5 ? Points.burstRestaurantBig : Points.burstRestaurant
                    restReasons[rid, default: []].append(
                        "\(n) \(tier.label)-tier votes within \(String(format: "%.1f", max(hours, 0.1)))h (\(windowSlice.first!.creationDate.formatted(date: .abbreviated, time: .shortened)))")
                    for p in windowSlice {
                        userScores[p.userID, default: 0] += Points.inBurst
                        userReasons[p.userID, default: []].append(
                            "Part of a \(n)-vote \(tier.label)-tier burst on one restaurant")
                    }
                    break   // one burst flag per (restaurant, tier)
                }
            }

            // Concentration: consensus flips if any single vote is removed
            if total >= 3 {
                let currentTier = consensusTier(votes)
                for i in votes.indices {
                    var copy = votes; copy.remove(at: i)
                    if consensusTier(copy) != currentTier {
                        restScores[rid, default: 0] += Points.concentration
                        restReasons[rid, default: []].append(
                            "Consensus (\(currentTier.label)) flips if one vote is removed — fragile")
                        break
                    }
                }
            }
        }

        // ─── Pass 3: cross-signal — flagged users voting extreme ─────
        // A restaurant receiving extreme votes FROM already-suspicious
        // accounts is the strongest "check this one" indicator.
        let flaggedUsers = Set(userScores.filter { $0.value >= Points.biasedMedium }.keys)
        for (rid, votes) in byRestaurant {
            let suspiciousExtremeVotes = votes.filter {
                flaggedUsers.contains($0.userID) && ($0.tier == .s || $0.tier == .f)
            }
            guard !suspiciousExtremeVotes.isEmpty else { continue }
            restScores[rid, default: 0] += suspiciousExtremeVotes.count * Points.suspiciousVoter
            restReasons[rid, default: []].append(
                "\(suspiciousExtremeVotes.count) extreme vote\(suspiciousExtremeVotes.count == 1 ? "" : "s") from flagged account\(suspiciousExtremeVotes.count == 1 ? "" : "s")")
        }

        // ─── Assemble ────────────────────────────────────────────────
        // De-dup repeated reasons (bursts can add the same line twice).
        let users: [UserAudit] = userScores
            .filter { $0.value > 0 }
            .map { uid, score in
                UserAudit(
                    userID: uid,
                    placements: (byUser[uid] ?? []).sorted { $0.creationDate > $1.creationDate },
                    score: score,
                    reasons: Array(NSOrderedSet(array: userReasons[uid] ?? [])) as! [String]
                )
            }
            .sorted { $0.score > $1.score }

        let restaurants: [RestaurantAudit] = restScores
            .filter { $0.value > 0 }
            .map { rid, score in
                RestaurantAudit(
                    restaurantID: rid,
                    votes: (byRestaurant[rid] ?? []).sorted { $0.creationDate > $1.creationDate },
                    score: score,
                    reasons: Array(NSOrderedSet(array: restReasons[rid] ?? [])) as! [String]
                )
            }
            .sorted { $0.score > $1.score }

        return AuditReport(
            suspiciousUsers: users,
            suspiciousRestaurants: restaurants,
            totalUsers: byUser.count,
            totalPlacements: placements.count,
            totalRestaurantsRanked: byRestaurant.count,
            generatedAt: Date()
        )
    }

    // ─── Helpers ─────────────────────────────────────────────────────
    private func consensusTier(_ votes: [AuditPlacement]) -> Tier {
        guard !votes.isEmpty else { return .f }
        let avg = votes.map { Double($0.tier.score) }.reduce(0, +) / Double(votes.count)
        switch avg {
        case 4.5...: return .s
        case 3.5...: return .a
        case 2.5...: return .b
        case 1.5...: return .c
        default: return .f
        }
    }
}
