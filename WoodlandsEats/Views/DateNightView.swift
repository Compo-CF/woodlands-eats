import SwiftUI

/// v3.1.1: the "Date Night Tiers" Valentine board (App Store In-App Event,
/// Jan 28 – Feb 15 2027). Live community consensus over date-night spots
/// (see `DateNight2027.isDateSpot`): a Top 10 plus a champion per vibe, and a
/// shortcut into Plan a Night Out.
struct DateNightView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.dismiss) private var dismiss

    @State private var tiers: [UUID: CommunityTier] = [:]
    @State private var loading = true
    @State private var prosOnly = false
    @State private var selected: Restaurant?

    private static let rose = Color(red: 0.91, green: 0.27, blue: 0.47)

    private struct Entry: Identifiable {
        let restaurant: Restaurant
        let info: CommunityTier
        var id: UUID { restaurant.id }
    }

    private struct Champion: Identifiable {
        let title: String
        let entry: Entry
        var id: String { title }
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
                        ProgressView("Finding the romantic spots…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if topTen.isEmpty && champions.isEmpty {
                        ContentUnavailableView {
                            Label("Not enough votes yet", systemImage: "heart")
                        } description: {
                            Text("Date-night spots need at least \(DateNight2027.minVotesTop) votes to make the board. Rank the places you've loved for a night out.")
                        }
                    } else {
                        if !topTen.isEmpty { topTenSection }
                        if !champions.isEmpty { championsSection }
                    }
                    planCard
                    Text("Date-night spots are sit-down restaurants that take reservations, are $$$ or up, or serve steak, seafood, Italian, French, sushi or Mediterranean. Standings come from live community tier averages.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .refreshable { await load() }
            .navigationTitle("Date Night Tiers")
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(.white)
            Text("DATE NIGHT TIERS")
                .font(.grotesk(30, .bold))
                .foregroundStyle(.white)
            Text(phaseLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Where north Houston goes for date night, ranked S to F by the people who went.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Self.rose, Color(red: 0.30, green: 0.10, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private var phaseLine: String {
        switch DateNight2027.phase() {
        case .upcoming: return "Valentine board opens Jan 28 · runs through Feb 15"
        case .live:
            let d = DateNight2027.daysLeft()
            return d == 1 ? "Valentine board · last day!" : "Valentine board · \(d) days left (through Feb 15)"
        case .ended: return "The Valentine board ran Jan 28 – Feb 15"
        }
    }

    private var topTenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Top 10 date-night spots", systemImage: "heart.circle.fill")
                .font(.grotesk(18, .bold))
            ForEach(Array(topTen.enumerated()), id: \.element.id) { idx, entry in
                Button { selected = entry.restaurant } label: {
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.grotesk(20, .bold))
                            .frame(width: 28)
                            .foregroundStyle(idx < 3 ? Self.rose : Color.secondary)
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
            Label("Best by vibe", systemImage: "sparkles")
                .font(.grotesk(18, .bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(champions) { item in
                    Button { selected = item.entry.restaurant } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Self.rose)
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

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plan your date", systemImage: "wineglass.fill")
                .font(.grotesk(18, .bold))
            Text("Let Plan a Night Out pick a spot from your tiers or the community's, near you and in your price range. Rank the places you've loved for a date to move them up this board.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                let router = tabRouter
                dismiss()
                router.selectedTab = .map
                // Let this sheet finish dismissing before the Map tab presents Night Out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    router.pendingNightOut = true
                }
            } label: {
                Label("Plan a date night", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.rose)
            Button {
                tabRouter.selectedTab = .browse
                dismiss()
            } label: {
                Label("Find spots to rank", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Self.rose)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func subtitle(for entry: Entry) -> String {
        var parts: [String] = []
        if let c = entry.restaurant.cuisines.first(where: { $0 != .other }) { parts.append(c.displayName) }
        parts.append(entry.restaurant.priceTier.displayName)
        parts.append(entry.restaurant.area.displayName)
        parts.append("\(entry.info.count) votes")
        return parts.joined(separator: " · ")
    }

    private var entries: [Entry] {
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        return tiers.compactMap { rid, info -> Entry? in
            guard let r = byID[rid], DateNight2027.isDateSpot(r) else { return nil }
            return Entry(restaurant: r, info: info)
        }
    }

    private static func better(_ a: Entry, _ b: Entry) -> Bool {
        if a.info.average != b.info.average { return a.info.average > b.info.average }
        if a.info.count != b.info.count { return a.info.count > b.info.count }
        return a.restaurant.name < b.restaurant.name
    }

    private var topTen: [Entry] {
        Array(entries.filter { $0.info.count >= DateNight2027.minVotesTop }
            .sorted(by: Self.better).prefix(10))
    }

    private var champions: [Champion] {
        let pool = entries.filter { $0.info.count >= DateNight2027.minVotesVibe }
        return DateNight2027.vibes.compactMap { vibe -> Champion? in
            guard let best = pool.filter({ vibe.test($0.restaurant) }).sorted(by: Self.better).first
            else { return nil }
            return Champion(title: vibe.title, entry: best)
        }
    }

    private func load() async {
        loading = tiers.isEmpty
        tiers = prosOnly ? await cloudKit.fetchProCommunityTiers() : await cloudKit.fetchAllCommunityTiers()
        loading = false
    }
}

/// v3.1.1: Community-tab banner shown only while Date Night Tiers is live.
struct DateNightBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date Night Tiers is live")
                        .font(.subheadline.weight(.bold))
                    Text(DateNight2027.daysLeft() == 1
                         ? "Last day. See the top date-night spots."
                         : "The best date-night spots · \(DateNight2027.daysLeft()) days left")
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
                LinearGradient(colors: [Color(red: 0.91, green: 0.27, blue: 0.47), Color(red: 0.30, green: 0.10, blue: 0.32)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date Night Tiers is live. Open the board.")
    }
}
