import SwiftUI
import CoreLocation
import UIKit

/// v2.2: "Plan a Night Out" — a decision engine on top of the tier data.
///
/// The tier list answers "is this place good?"; this answers the question
/// people actually have on a Friday: "where should we go tonight?" The user
/// picks a cuisine (or leaves it open), a location (near me + radius, or a
/// specific area), a quality bar (tier floor), and a price range — then
/// chooses WHICH ranking to trust (their own list, the community, Foodie
/// Pros, or a friends-only consensus). We match all of that against the
/// chosen source and surface a single "Tonight's Pick" with a couple of
/// alternates and a "Spin again."
///
/// Reuses everything already in the app: RestaurantStore (catalog +
/// userLocation + confirmedClosedIDs), TierListStore (personal placements),
/// the three CloudKit community fetches, and RestaurantDetailView for the
/// deep-dive. Pure UX — no IAP, no new CloudKit schema. Presented as a
/// sheet from both the Map and Browse tabs.
struct NightOutView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(FriendsStore.self) private var friendsStore
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.dismiss) private var dismiss

    // MARK: Inputs
    @State private var source: NightOutSource = .myTiers
    @State private var cuisines: Set<Cuisine> = []
    @State private var useNearMe = true
    @State private var radiusMiles: Double = 10
    @State private var selectedArea: Area = .woodlands
    @State private var floor: TierFloor = .sb
    @State private var prices: Set<PriceTier> = []

    // MARK: Runtime
    /// Cached non-personal source tiers + which source they belong to, so
    /// switching source refetches but re-running the same source doesn't.
    @State private var sourceTiers: [UUID: CommunityTier] = [:]
    @State private var loadedSource: NightOutSource?
    @State private var isSearching = false
    @State private var ranked: [NightOutPick] = []
    @State private var spinIndex = 0
    @State private var showResult = false
    @State private var hasSearched = false

    private let radiusOptions: [Double] = [2, 5, 10, 25]

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                cuisineSection
                locationSection
                qualitySection
                priceSection
                findSection
                if hasSearched && ranked.isEmpty && !isSearching {
                    relaxSection
                }
            }
            .navigationTitle("Plan a Night Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showResult) {
                NightOutResultView(
                    ranked: ranked,
                    spinIndex: $spinIndex,
                    source: source,
                    useNearMe: useNearMe
                )
            }
        }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            Picker("Rank by", selection: $source) {
                ForEach(NightOutSource.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
        } header: {
            Text("Whose rankings")
        } footer: {
            Text(source.footer(friendCount: friendsStore.count,
                               myCount: tierStore.rankedCount))
        }
    }

    private var cuisineSection: some View {
        Section {
            ChipCloud(
                items: Cuisine.allCases,
                isSelected: { cuisines.contains($0) },
                label: { $0.displayName },
                toggle: { c in
                    if cuisines.contains(c) { cuisines.remove(c) } else { cuisines.insert(c) }
                }
            )
        } header: {
            Text("Cuisine")
        } footer: {
            Text(cuisines.isEmpty
                 ? "Surprise me — open to anything."
                 : "\(cuisines.count) selected. A spot matches if it's tagged any of these.")
        }
    }

    private var locationSection: some View {
        Section {
            Picker("Where", selection: $useNearMe) {
                Text("Near me").tag(true)
                Text("By area").tag(false)
            }
            .pickerStyle(.segmented)

            if useNearMe {
                if store.userLocation == nil {
                    Label("Location is off — turn it on or search by area instead.",
                          systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Picker("Within", selection: $radiusMiles) {
                    ForEach(radiusOptions, id: \.self) { m in
                        Text("\(Int(m)) mi").tag(m)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Area", selection: $selectedArea) {
                    ForEach(Area.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
            }
        } header: {
            Text("Where")
        }
    }

    private var qualitySection: some View {
        Section {
            Picker("At least", selection: $floor) {
                ForEach(TierFloor.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("How good")
        } footer: {
            Text(floor.footer)
        }
    }

    private var priceSection: some View {
        Section {
            ChipCloud(
                items: PriceTier.allCases,
                isSelected: { prices.contains($0) },
                label: { $0.displayName },
                toggle: { p in
                    if prices.contains(p) { prices.remove(p) } else { prices.insert(p) }
                }
            )
        } header: {
            Text("Price")
        } footer: {
            Text(prices.isEmpty ? "Any price." : "Only the selected price levels.")
        }
    }

    private var findSection: some View {
        Section {
            Button {
                Task { await find() }
            } label: {
                HStack {
                    Spacer()
                    if isSearching {
                        ProgressView().tint(.white)
                    } else {
                        Label("Find Tonight's Pick", systemImage: "sparkles")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Tier.s.color)
            .foregroundStyle(.white)
            .disabled(isSearching || (useNearMe && store.userLocation == nil))
        }
    }

    private var relaxSection: some View {
        Section {
            ForEach(relaxOptions, id: \.label) { opt in
                Button {
                    opt.action()
                    Task { await find() }
                } label: {
                    Label(opt.label, systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        } header: {
            Text("No matches — try loosening up")
        } footer: {
            Text("Nothing hit all your filters. Widen one and we'll look again.")
        }
    }

    // MARK: - Search

    private func find() async {
        isSearching = true
        defer { isSearching = false }
        if source != .myTiers, loadedSource != source {
            sourceTiers = await fetchTiers(for: source)
            loadedSource = source
        }
        let results = makeRanked()
        ranked = results
        spinIndex = 0
        hasSearched = true
        showResult = !results.isEmpty
    }

    private func fetchTiers(for source: NightOutSource) async -> [UUID: CommunityTier] {
        switch source {
        case .myTiers:  return [:]
        case .everyone: return await cloudKit.fetchAllCommunityTiers()
        case .pros:     return await cloudKit.fetchProCommunityTiers()
        case .friends:  return await cloudKit.fetchFriendsCommunityTiers(friendIDs: friendsStore.friendIDs)
        }
    }

    /// The matcher: filter by every input, score, sort best-first.
    private func makeRanked() -> [NightOutPick] {
        let loc = store.userLocation
        let closed = store.confirmedClosedIDs
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })

        var scored: [(pick: NightOutPick, score: Double)] = []

        func consider(_ r: Restaurant, tier: Tier, count: Int?) {
            guard !closed.contains(r.id) else { return }
            guard tier.score >= floor.minScore else { return }
            if !cuisines.isEmpty && cuisines.isDisjoint(with: Set(r.cuisines)) { return }
            if !prices.isEmpty && !prices.contains(r.priceTier) { return }

            var miles: Double?
            if useNearMe {
                guard let loc else { return }
                let m = r.distance(from: loc) / 1609.344
                guard m <= radiusMiles else { return }
                miles = m
            } else {
                guard r.area == selectedArea else { return }
            }

            // Score: tier dominates, then proximity, then crowd confidence.
            var score = Double(tier.score) * 100
            if let miles { score += max(0, (radiusMiles - miles) / radiusMiles) * 25 }
            if let count { score += Double(min(count, 20)) }

            scored.append((NightOutPick(restaurant: r, tier: tier, miles: miles, rankCount: count), score))
        }

        if source == .myTiers {
            for (rid, tier) in tierStore.placements {
                if let r = byID[rid] { consider(r, tier: tier, count: nil) }
            }
        } else {
            for (rid, info) in sourceTiers {
                if let r = byID[rid] { consider(r, tier: info.tier, count: info.count) }
            }
        }

        return scored.sorted { $0.score > $1.score }.map(\.pick)
    }

    // MARK: - Relax suggestions

    private var relaxOptions: [(label: String, action: () -> Void)] {
        var opts: [(String, () -> Void)] = []
        if useNearMe, let next = radiusOptions.first(where: { $0 > radiusMiles }) {
            opts.append(("Search a wider area (\(Int(next)) mi)", { radiusMiles = next }))
        }
        if let lower = floor.loosened {
            opts.append(("Include \(lower.rawValue) spots", { floor = lower }))
        }
        if !cuisines.isEmpty {
            opts.append(("Open it up to any cuisine", { cuisines = [] }))
        }
        if !prices.isEmpty {
            opts.append(("Allow any price", { prices = [] }))
        }
        return opts
    }
}

// MARK: - Result

/// Tonight's Pick + alternates. Hero = ranked[spinIndex]; "Spin again"
/// advances the index so repeated taps walk down the honest best-first
/// list rather than random-jumping. Fetches the pick's placement note (the
/// "why") lazily for the hero only.
private struct NightOutResultView: View {
    let ranked: [NightOutPick]
    @Binding var spinIndex: Int
    let source: NightOutSource
    let useNearMe: Bool

    @Environment(CloudKitService.self) private var cloudKit
    @State private var heroNote: String?
    @State private var selected: Restaurant?

    private var hero: NightOutPick { ranked[spinIndex % max(ranked.count, 1)] }
    private var alternates: [NightOutPick] {
        guard ranked.count > 1 else { return [] }
        let heroID = hero.id
        return Array(ranked.filter { $0.id != heroID }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                if !alternates.isEmpty { alternatesBlock }
                Text("Matched against \(source.longName) · \(ranked.count) spot\(ranked.count == 1 ? "" : "s") fit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Tonight's Pick")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    spinIndex += 1
                } label: {
                    Label("Spin again", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(ranked.count <= 1)
            }
        }
        .task(id: hero.id) { await loadNote() }
        .sheet(item: $selected) { r in
            NavigationStack { RestaurantDetailView(restaurant: r) }
                .presentationDetents([.medium, .large])
        }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            Text(hero.tier.label)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(hero.tier.color, in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 6) {
                Text(hero.restaurant.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(hero.restaurant.cuisineSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                metaChip(hero.restaurant.priceTier.displayName, system: "dollarsign.circle")
                if let miles = hero.miles {
                    metaChip(distanceString(miles), system: "location")
                } else {
                    metaChip(hero.restaurant.area.displayName, system: "mappin.and.ellipse")
                }
                if let count = hero.rankCount {
                    metaChip("\(count) ranked", system: "person.3")
                }
            }
            .font(.footnote)

            if let note = heroNote, !note.isEmpty {
                Text("“\(note)”")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    selected = hero.restaurant
                } label: {
                    Label("See details", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    openDirections(to: hero.restaurant)
                } label: {
                    Label("Directions", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tier.s.color)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var alternatesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or maybe…")
                .font(.headline)
                .padding(.leading, 4)
            ForEach(alternates) { pick in
                Button { selected = pick.restaurant } label: {
                    HStack(spacing: 12) {
                        Text(pick.tier.label)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(pick.tier.color, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pick.restaurant.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(pick.restaurant.primaryCuisine.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let miles = pick.miles {
                            Text(distanceString(miles))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaChip(_ text: String, system: String) -> some View {
        Label(text, systemImage: system)
            .foregroundStyle(.secondary)
    }

    private func distanceString(_ miles: Double) -> String {
        miles < 0.1 ? "< 0.1 mi" : String(format: "%.1f mi", miles)
    }

    private func loadNote() async {
        heroNote = nil
        let note: String?
        if source == .myTiers {
            note = await cloudKit.fetchMyNote(restaurantID: hero.restaurant.id)
        } else {
            note = await cloudKit.fetchCommunityNotes(restaurantID: hero.restaurant.id).first?.text
        }
        heroNote = note
    }

    private func openDirections(to r: Restaurant) {
        let name = r.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "http://maps.apple.com/?daddr=\(r.latitude),\(r.longitude)&q=\(name)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Supporting types

enum NightOutSource: String, CaseIterable, Identifiable {
    case myTiers  = "My Tiers"
    case everyone = "Community"
    case pros     = "Foodie Pros"
    case friends  = "Friends"

    var id: String { rawValue }

    var longName: String {
        switch self {
        case .myTiers:  "your tier list"
        case .everyone: "the community"
        case .pros:     "Foodie Pros"
        case .friends:  "people you follow"
        }
    }

    func footer(friendCount: Int, myCount: Int) -> String {
        switch self {
        case .myTiers:
            return myCount == 0
                ? "You haven't ranked anything yet — try Community for now."
                : "Pick from your own \(myCount) ranked spots."
        case .everyone: return "The crowd's consensus tier for each spot."
        case .pros:     return "Consensus from the app's top rankers."
        case .friends:
            return friendCount == 0
                ? "You're not following anyone yet. Follow friends to unlock this."
                : "Consensus from the \(friendCount) people you follow."
        }
    }
}

/// Minimum acceptable tier — a floor, not an exact match, so the user gets
/// options instead of dead ends.
enum TierFloor: String, CaseIterable, Identifiable {
    case sOnly = "S"
    case sa    = "S–A"
    case sb    = "S–B"
    case any   = "Any"

    var id: String { rawValue }

    var minScore: Int {
        switch self {
        case .sOnly: 5
        case .sa:    4
        case .sb:    3
        case .any:   1
        }
    }

    var footer: String {
        switch self {
        case .sOnly: "Only S-tier — the elite spots."
        case .sa:    "S and A tier."
        case .sb:    "S, A and B — anything solid or better."
        case .any:   "Anything that's been ranked."
        }
    }

    /// The next-looser floor, for the empty-state relax suggestion. nil at `.any`.
    var loosened: TierFloor? {
        switch self {
        case .sOnly: .sa
        case .sa:    .sb
        case .sb:    .any
        case .any:   nil
        }
    }
}

struct NightOutPick: Identifiable {
    let restaurant: Restaurant
    let tier: Tier
    let miles: Double?
    let rankCount: Int?
    var id: UUID { restaurant.id }
}

// MARK: - Chip cloud

/// A wrapping multi-select chip grid used for cuisine + price. Generic over
/// any Hashable item so both sections share one implementation.
private struct ChipCloud<Item: Hashable>: View {
    let items: [Item]
    let isSelected: (Item) -> Bool
    let label: (Item) -> String
    let toggle: (Item) -> Void

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = isSelected(item)
                Button { toggle(item) } label: {
                    Text(label(item))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(on ? Tier.s.color : Color(.secondarySystemBackground),
                                    in: Capsule())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
