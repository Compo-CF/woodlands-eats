import SwiftUI

/// What each tier means, with one paragraph per letter. Auto-presented on
/// first launch (gated by `@AppStorage("WoodlandsEats.hasSeenTierGuide")`)
/// and reachable any time later from Profile -> "Tier guide".
///
/// Driven entirely by the `Tier` enum's `label`, `color`, and `blurb` so
/// adding or renaming tiers updates this view automatically.
struct TierGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro

                    VStack(spacing: 14) {
                        ForEach(Tier.allCases) { tier in
                            tierRow(tier)
                        }
                    }

                    howToPlace
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Tier guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How tiers work")
                .font(.title3.weight(.semibold))
            Text("S-Tier Eats uses a five-letter tier list instead of a star rating. The point: force a real opinion. Five stars on every other app collapses into a 3.9-to-4.4 blob — useless. Slotting a place into S, A, B, C, or F gives a clear honest signal — to your future self, and to everyone else ranking too.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func tierRow(_ tier: Tier) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(tier.label)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(tier.blurb)
                    .font(.headline)
                Text(detail(for: tier))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detail(for tier: Tier) -> String {
        switch tier {
        case .s:
            return "The places you'd recommend without thinking. You'll drive past three other options to get here. Most people end up with 5-15% of their list at S."
        case .a:
            return "Reliably great. You'd actively suggest these to a friend visiting from out of town. Usually 15-30% of a fully filled-out list."
        case .b:
            return "Solid. Happy to eat here again, but it's not something you'd plan a night around. The biggest tier for most users — and that's fine."
        case .c:
            return "Functional. You'd go if someone else picked it or if you were already in the area. Not actively avoiding, but not seeking out either."
        case .f:
            return "Skip. Either the food, the service, or the value missed badly. An honest F is more useful than a polite B — it helps the community avoid bad nights."
        }
    }

    private var howToPlace: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to place a restaurant")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                step("Tap a restaurant from the map or the Browse list.")
                step("Under \"Your tier,\" tap the letter that fits.")
                step("Tap again on the same letter to clear it.")
                step("Your rankings sync across your devices via iCloud and feed the community average anonymously.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .padding(.top, 2)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
