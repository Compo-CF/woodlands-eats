import SwiftUI

/// v3.1.1: the "Best of 2026" year-end board (App Store In-App Event,
/// Dec 10 2026 – Jan 5 2027). Built from the same live community consensus as
/// the Community tab: an overall Top 10 plus a champion per cuisine. Every spot
/// ranked during the event moves these standings.
struct BestOf2026View: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.dismiss) private var dismiss

    @State private var tiers: [UUID: CommunityTier] = [:]
    @State private var loading = true
    @State private var prosOnly = false
    @State private var selected: Restaurant?

    private struct Entry: Identifiable {
        let restaurant: Restaurant
        let info: CommunityTier
        var id: UUID { restaurant.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    Picker("Who voted", selection: $prosOnly) {
                        Text("Everyone").tag(false)
                        Text("Foodie Pros").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if loading {
                        ProgressView("Tallying the votes…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if topTen.isEmpty && champions.isEmpty {
                        ContentUnavailableView {
                            Label("Not enough votes yet", systemImage: "trophy")
                        } description: {
                            Text("Spots need at least \(BestOf2026.minVotesTop) votes to make the board. Rank the places you ate this year to get it going.")
                        }
                    } else {
                        if !topTen.isEmpty { topTenSection }
                        if !champions.isEmpty { championsSection }
                    }
                    voteCard
                    Text("Standings come from the live community tier averages. Ties go to the spot with more votes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .refreshable { await load() }
            .navigationTitle("Best of 2026")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .onChange(of: prosOnly) { _, _ in Task { await load() } }
            .sheet(item: $selected) { restaurant in
                NavigationStack {
                    RestaurantDetailView(restaurant: restaurant)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tier.allCases) { TierBadge(tier: $0, size: 22) }
            }
            Text("BEST OF 2026")
                .font(.grotesk(32, .bold))
                .foregroundStyle(.white)
            Text(phaseLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("North Houston's year in food, ranked S to F by the people who ate it.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.nightOut, Color(red: 0.16, green: 0.12, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private var phaseLine: String {
        switch BestOf2026.phase() {
        case .upcoming: return "Community vote opens Dec 10 · runs through Jan 5"
        case .live:
            let d = BestOf2026.daysLeft()
            return d == 1 ? "Community vote · last day!" : "Community vote · \(d) days left (through Jan 5)"
        case .ended: return "Final standings · the vote ran Dec 10 – Jan 5"
        }
    }

    private var topTenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("The 2026 Top 10", systemImage: "trophy.fill")
            ForEach(Array(topTen.enumerated()), id: \.element.id) { idx, entry in
                Button { selected = entry.restaurant } label: {
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.grotesk(20, .bold))
                            .frame(width: 28)
                            .foregroundStyle(idx < 3 ? Color.nightOut : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.restaurant.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(subtitle(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        TierBadge(tier: entry.info.tier, size: 30)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var championsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Category champions", systemImage: "crown.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(champions) { item in
                    Button { selected = item.entry.restaurant } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Best \(item.cuisine.displayName)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.nightOut)
                                .lineLimit(1)
                            Text(item.entry.restaurant.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                TierBadge(tier: item.entry.info.tier, size: 20)
                                Text("\(item.entry.info.count) votes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var voteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(BestOf2026.phase() == .ended ? "Keep ranking" : "Cast your votes",
                          systemImage: "checkmark.seal.fill")
            Text(BestOf2026.phase() == .ended
                 ? "The board keeps moving as people rank. Add the spots you've tried."
                 : "Every spot you rank counts toward the 2026 board. Open any restaurant and drop it into a tier.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                tabRouter.selectedTab = .browse
                dismiss()
            } label: {
                Label("Find spots to rank", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.nightOut)
            NavigationLink {
                MyStatsView()
            } label: {
                Label("Share my 2026 in Food", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.nightOut)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.grotesk(18, .bold))
            .foregroundStyle(.primary)
    }

    private func subtitle(for entry: Entry) -> String {
        var parts: [String] = []
        if let c = entry.restaurant.cuisines.first(where: { $0 != .other }) { parts.append(c.displayName) }
        parts.append(entry.restaurant.area.displayName)
        parts.append("\(entry.info.count) votes")
        return parts.joined(separator: " · ")
    }

    // MARK: - Standings

    private var entries: [Entry] {
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        return tiers.compactMap { rid, info in
            byID[rid].map { Entry(restaurant: $0, info: info) }
        }
    }

    private static func better(_ a: Entry, _ b: Entry) -> Bool {
        if a.info.average != b.info.average { return a.info.average > b.info.average }
        if a.info.count != b.info.count { return a.info.count > b.info.count }
        return a.restaurant.name < b.restaurant.name
    }

    private var topTen: [Entry] {
        Array(entries
            .filter { $0.info.count >= BestOf2026.minVotesTop }
            .sorted(by: Self.better)
            .prefix(10))
    }

    private struct Champion: Identifiable {
        let cuisine: Cuisine
        let entry: Entry
        var id: String { cuisine.rawValue }
    }

    private var champions: [Champion] {
        let pool = entries.filter { $0.info.count >= BestOf2026.minVotesCategory }
        return BestOf2026.categories.compactMap { c -> Champion? in
            guard let best = pool.filter({ $0.restaurant.cuisines.contains(c) })
                .sorted(by: Self.better)
                .first else { return nil }
            return Champion(cuisine: c, entry: best)
        }
    }

    private func load() async {
        loading = tiers.isEmpty
        let fresh = prosOnly
            ? await cloudKit.fetchProCommunityTiers()
            : await cloudKit.fetchAllCommunityTiers()
        tiers = fresh
        loading = false
    }
}

/// v3.1.1: Community-tab banner shown only while the Best of 2026 event is live.
struct BestOf2026Banner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best of 2026 is live")
                        .font(.subheadline.weight(.bold))
                    Text(BestOf2026.daysLeft() == 1
                         ? "Last day to vote. See the year's top spots."
                         : "Vote through Jan 5 · \(BestOf2026.daysLeft()) days left")
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(
                LinearGradient(colors: [Color.nightOut, Color(red: 0.16, green: 0.12, blue: 0.36)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Best of 2026 is live. Open the board.")
    }
}
