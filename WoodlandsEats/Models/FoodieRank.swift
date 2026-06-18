import SwiftUI

/// v1.4: gamified rank progression based on the number of restaurants
/// the user has placed in any tier. Five rungs from Newcomer to
/// Tastemaker, with thresholds calibrated for the long tail of
/// engagement (most users land in the first 1-3 tiers; reaching
/// Tastemaker requires real investment).
///
/// Distinct from `FoodieProfile.status` ("approved" Foodie Pros) —
/// that's editorial trust, this is participation volume. A user can
/// be a Tastemaker without being a Foodie Pro, and vice versa.
///
/// All computation is client-side from TierListStore.placements.count;
/// no CloudKit involvement. Tier-up celebrations are gated by
/// @AppStorage("WoodlandsEats.lastCelebratedRank") in ContentView to
/// prevent re-celebrating the same milestone on every launch and to
/// migrate v1.3 → v1.4 upgraders silently (anyone already past
/// Newcomer at launch is recorded without celebration so they don't
/// get spammed for tiers they earned before this feature existed).
enum FoodieRank: Int, CaseIterable, Identifiable, Comparable {
    case newcomer = 0, foodie, critic, connoisseur, tastemaker

    var id: Int { rawValue }

    /// Minimum placements to be classified at this rank. The first
    /// placement (count == 1) puts the user at Newcomer; placements
    /// below 1 yield nil from `from(placementCount:)`.
    var minPlacements: Int {
        switch self {
        case .newcomer:    1
        case .foodie:      5
        case .critic:      15
        case .connoisseur: 30
        case .tastemaker:  60
        }
    }

    var displayName: String {
        switch self {
        case .newcomer:    "Newcomer"
        case .foodie:      "Foodie"
        case .critic:      "Critic"
        case .connoisseur: "Connoisseur"
        case .tastemaker:  "Tastemaker"
        }
    }

    /// SF Symbol name. Filled variants chosen for the higher tiers so
    /// the visual weight reflects status progression.
    var symbolName: String {
        switch self {
        case .newcomer:    "leaf"
        case .foodie:      "fork.knife"
        case .critic:      "pencil"
        case .connoisseur: "wineglass.fill"
        case .tastemaker:  "crown.fill"
        }
    }

    /// Primary accent — used for the icon stroke + tier name color.
    /// Matches the v1.4 roadmap visualization (600-stop of the ramp).
    var color: Color {
        switch self {
        case .newcomer:    Color(red: 0.373, green: 0.369, blue: 0.353) // gray-600
        case .foodie:      Color(red: 0.059, green: 0.431, blue: 0.337) // teal-600
        case .critic:      Color(red: 0.522, green: 0.310, blue: 0.043) // amber-600
        case .connoisseur: Color(red: 0.600, green: 0.235, blue: 0.114) // coral-600
        case .tastemaker:  Color(red: 0.235, green: 0.204, blue: 0.537) // purple-600
        }
    }

    /// Background tint for the badge circle — 50-stop of the same ramp.
    var tintColor: Color {
        switch self {
        case .newcomer:    Color(red: 0.945, green: 0.937, blue: 0.910) // gray-50
        case .foodie:      Color(red: 0.882, green: 0.961, blue: 0.933) // teal-50
        case .critic:      Color(red: 0.980, green: 0.933, blue: 0.855) // amber-50
        case .connoisseur: Color(red: 0.980, green: 0.925, blue: 0.906) // coral-50
        case .tastemaker:  Color(red: 0.933, green: 0.929, blue: 0.996) // purple-50
        }
    }

    var blurb: String {
        switch self {
        case .newcomer:    "Just trying things out."
        case .foodie:      "Building a real list."
        case .critic:      "Opinions you can trust."
        case .connoisseur: "Deep local knowledge."
        case .tastemaker:  "Shapes the local scene."
        }
    }

    /// The rank for a given placement count. `nil` when the user has
    /// zero placements (no rank yet — UI shows a prompt to rank a
    /// first spot instead of awarding Newcomer to someone who hasn't
    /// started).
    static func from(placementCount: Int) -> FoodieRank? {
        guard placementCount >= 1 else { return nil }
        return FoodieRank.allCases.reversed().first { placementCount >= $0.minPlacements }
    }

    /// The next rank up, or nil if already at the top.
    var next: FoodieRank? { FoodieRank(rawValue: rawValue + 1) }

    /// Placements remaining to reach the next rank. nil at top.
    func placementsToNext(currentCount: Int) -> Int? {
        guard let next else { return nil }
        return max(0, next.minPlacements - currentCount)
    }

    /// Progress fraction (0...1) from this tier's floor to the next.
    /// Returns 1.0 when already at the top tier.
    func progress(currentCount: Int) -> Double {
        guard let next else { return 1.0 }
        let span = Double(next.minPlacements - minPlacements)
        guard span > 0 else { return 1.0 }
        let within = Double(currentCount - minPlacements)
        return min(1.0, max(0.0, within / span))
    }

    static func < (lhs: FoodieRank, rhs: FoodieRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
