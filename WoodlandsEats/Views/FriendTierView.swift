import SwiftUI

/// v1.7 Feature C: Read-only view of a friend's tier list, presented as
/// a sheet when the user opens a `https://compo-cf.github.io/woodlands-eats/tier/<userID>`
/// universal link (or the `stier://tier/<userID>` custom scheme fallback).
///
/// Fetches the friend's placements + display name from CloudKit on appear,
/// renders the same S/A/B/C/F layout as MyTiersView but with no edit
/// affordances — tapping a restaurant opens the standard detail sheet
/// so the recipient can place it in their OWN tier list.
struct FriendTierView: View {
    /// The friend's CloudKit user record name — opaque iCloud identifier.
    /// Parsed from the share-link path.
    let userID: String

    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var placements: [(restaurantID: UUID, tier: Tier)] = []
    @State private var loading: Bool = true
    @State private var selected: Restaurant?

    private var byTier: [Tier: [Restaurant]] {
        // index placements by tier, hydrating against the local catalog.
        // If a friend ranked a restaurant we no longer carry (closed /
        // dedup-removed / out-of-area), it just doesn't appear here.
        let lookup = Dictionary(grouping: store.restaurants, by: \.id)
        var out: [Tier: [Restaurant]] = [:]
        for (rid, tier) in placements {
            guard let restaurant = lookup[rid]?.first else { continue }
            out[tier, default: []].append(restaurant)
        }
        for tier in Tier.allCases {
            out[tier]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return out
    }

    private var rankedCount: Int { placements.count }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rankedCount == 0 {
                    ContentUnavailableView {
                        Label("No rankings yet", systemImage: "list.number")
                    } description: {
                        Text("This person hasn't ranked any restaurants yet, or the link is no longer valid.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Tier.allCases) { tier in
                                FriendTierRow(
                                    tier: tier,
                                    restaurants: byTier[tier] ?? [],
                                    onTap: { selected = $0 }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { r in
                NavigationStack {
                    RestaurantDetailView(restaurant: r)
                }
                .presentationDetents([.medium, .large])
            }
            .task { await load() }
        }
    }

    private var navTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Tier List" : "\(trimmed)'s Tiers"
    }

    private func load() async {
        async let placementsTask = cloudKit.fetchPlacements(forUserID: userID)
        async let profileTask = cloudKit.fetchProfile(forUserID: userID)
        let (p, prof) = await (placementsTask, profileTask)
        placements = p
        displayName = prof.displayName
        loading = false
    }
}

private struct FriendTierRow: View {
    let tier: Tier
    let restaurants: [Restaurant]
    let onTap: (Restaurant) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tier.label)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 64)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 14))

            if restaurants.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(restaurants) { r in
                            Button {
                                onTap(r)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(r.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text(r.primaryCuisine.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 96, height: 52)
                                .padding(6)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
