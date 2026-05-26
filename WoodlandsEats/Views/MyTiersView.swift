import SwiftUI

struct MyTiersView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @State private var selected: Restaurant?

    var body: some View {
        NavigationStack {
            Group {
                if tierStore.rankedCount == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Tier.allCases) { tier in
                                TierRow(
                                    tier: tier,
                                    restaurants: tierStore.restaurants(in: tier, from: store.restaurants),
                                    onTap: { selected = $0 }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My Tiers")
            .sheet(item: $selected) { r in
                NavigationStack {
                    RestaurantDetailView(restaurant: r)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Build your tier list", systemImage: "list.number")
        } description: {
            Text("Open a restaurant from the Map or Browse tab and drop it into S, A, B, C, or F. Your ranked spots collect here.")
        }
    }
}

private struct TierRow: View {
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
