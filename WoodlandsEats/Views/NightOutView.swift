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
    /// Non-nil when a search can't proceed (empty source, or the crowd
    /// fetch timed out) — shown instead of leaving the spinner hanging.
    @State private var searchError: String?

    private let radiusOptions: [Double] = [2, 5, 10, 25]

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                sourceSection
                cuisineSection
                locationSection
                qualitySection
                priceSection
                findSection
                if let searchError, !isSearching {
                    Section {
                        Label(searchError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if hasSearched && ranked.isEmpty && !isSearching && searchError == nil {
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

    /// A colorful full-bleed banner header so the sheet reads as a
    /// distinct, fun feature the moment it opens.
    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text("Tonight's the night")
                    .font(.title3.weight(.bold))
                Text("Tell us the vibe — we'll pick the spot.")
                    .font(.subheadline)
                    .opacity(0.95)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .foregroundStyle(.white)
            .listRowInsets(EdgeInsets())
            .listRowBackground(LinearGradient.nightOut)
        }
    }

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
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(LinearGradient.nightOut)
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
        searchError = nil
        defer { isSearching = false }

        // Guard the sources that can't produce results, so the user gets a
        // clear message instead of an empty spinner or dead-end.
        if source == .myTiers, tierStore.placements.isEmpty {
            ranked = []; hasSearched = true
            searchError = "You haven't ranked any spots yet. Rank a few, or switch to Community."
            return
        }
        if source == .friends, friendsStore.friendIDs.isEmpty {
            ranked = []; hasSearched = true
            searchError = "You're not following anyone yet. Follow friends to use their rankings."
            return
        }

        // Non-personal sources need CloudKit data. Render instantly from the
        // launch-warmed cache when present, then bound the live refresh with
        // a timeout so the spinner can NEVER hang (the old bug).
        if source != .myTiers, loadedSource != source {
            if let cached = Self.cachedTiers(for: source) {
                sourceTiers = cached
                loadedSource = source
            }
            let live = await fetchTiersWithTimeout(source)
            if !live.isEmpty {
                sourceTiers = live
                loadedSource = source
            } else if loadedSource != source {
                // No cache AND the live fetch timed out / came back empty.
                ranked = []; hasSearched = true
                searchError = "Couldn't load \(source.longName) rankings — check your connection and try again."
                return
            }
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

    /// Runs the crowd-tier fetch against a wall-clock timeout. Whichever
    /// finishes first wins; if the timeout fires first we return an empty
    /// dictionary and the caller surfaces a retry message. This is what
    /// guarantees the Find spinner can't hang on a slow/stalled CloudKit call.
    private func fetchTiersWithTimeout(_ source: NightOutSource,
                                       seconds: Double = 12) async -> [UUID: CommunityTier] {
        await withTaskGroup(of: [UUID: CommunityTier]?.self) { group in
            group.addTask { await fetchTiers(for: source) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = (await group.next()) ?? nil
            group.cancelAll()
            return first ?? [:]
        }
    }

    /// Reads the community/pro tiers the Community tab already warms into
    /// UserDefaults at launch (same key + shape), so Night Out renders
    /// instantly on a warm cache instead of waiting on a fresh CloudKit walk.
    private static func cachedTiers(for source: NightOutSource) -> [UUID: CommunityTier]? {
        let suffix: String
        switch source {
        case .everyone: suffix = "everyone"
        case .pros:     suffix = "pros"
        default:        return nil   // friends board isn't cached
        }
        let key = "WoodlandsEats.communityCache.\(suffix)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedTiersDTO.self, from: data) else {
            return nil
        }
        var out: [UUID: CommunityTier] = [:]
        for e in cached.entries {
            if let id = UUID(uuidString: e.restaurantID), let t = Tier(rawValue: e.tierRaw) {
                out[id] = CommunityTier(tier: t, count: e.count, average: e.average)
            }
        }
        return out.isEmpty ? nil : out
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
        .background(hero.tier.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(hero.tier.color.opacity(0.35), lineWidth: 1.5)
        )
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

/// Decode-only mirror of CommunityTiersView's private cache payload
/// (same UserDefaults key + field names), so Night Out can read the tiers
/// the Community tab already warms at launch without refetching.
private struct CachedTiersDTO: Codable {
    let timestamp: Date
    let entries: [Entry]
    struct Entry: Codable {
        let restaurantID: String
        let tierRaw: String
        let count: Int
        let average: Double
    }
}

// MARK: - Shared entry point + styling

extension Color {
    /// v2.2: the single bold "night out" accent — a modern indigo-violet
    /// (data-viz-era accent). Stands out on the Map/Browse without a
    /// rainbow; drives the pill, header, and Find button.
    static let nightOut = Color(red: 0.42, green: 0.36, blue: 0.96)
}

extension LinearGradient {
    /// Flat fill exposed as a LinearGradient so existing call sites
    /// (listRowBackground / background) stay unchanged.
    static var nightOut: LinearGradient {
        LinearGradient(colors: [.nightOut, .nightOut],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// v2.2: the prominent, colorful entry point that drives users into Plan a
/// Night Out. `compact` renders a pill (used as a floating Map overlay);
/// otherwise a full-width card (used as the Browse list header).
struct NightOutCTA: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(compact ? .subheadline.weight(.bold) : .title2.weight(.bold))
                if compact {
                    Text("Plan a Night Out")
                        .font(.subheadline.weight(.bold))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan a Night Out")
                            .font(.headline.weight(.bold))
                        Text("Can't decide? Get tonight's pick.")
                            .font(.caption)
                            .opacity(0.95)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
            // compact horizontal padding widened ~20% (20→42) so the Map
            // pill reads as a deliberate, prominent button at the top.
            .padding(.horizontal, compact ? 42 : 16)
            .padding(.vertical, compact ? 12 : 15)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(LinearGradient.nightOut,
                        in: RoundedRectangle(cornerRadius: compact ? 26 : 16, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
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
