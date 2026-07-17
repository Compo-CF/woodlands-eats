import SwiftUI
import Charts

/// v1.8: full admin dashboard — supersedes the inline Stats card that
/// lived in ProfileView. One CloudKit placement walk powers everything;
/// the FoodieProfile count is a separate cheap query.
///
/// Sections:
///   Momentum      — 7-day placements / new users / active users, each
///                   with a delta arrow vs the PRIOR 7 days
///   Activity      — placements-per-day bar chart, last 14 days
///   Totals        — users, profiles, pros, placements, coverage
///   Tier mix      — S/A/B/C/F distribution across all placements
///   Users by rank — FoodieRank ladder
///   Top rankers   — 5 most active accounts
///   Hot spots     — 10 most-voted restaurants w/ consensus tier
///   Live feed     — 12 most recent placements
struct AdminDashboardView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store

    @State private var metrics: DashboardMetrics?
    @State private var loading = false

    var body: some View {
        Group {
            if loading {
                ProgressView("Crunching CloudKit data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let m = metrics {
                dashboard(m)
            } else {
                ContentUnavailableView {
                    Label("Load dashboard", systemImage: "gauge.with.dots.needle.67percent")
                } description: {
                    Text("Tap refresh to pull all placement data from CloudKit.")
                }
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }
                .disabled(loading)
            }
        }
        .task { if metrics == nil { await load() } }
    }

    // ─── Layout ──────────────────────────────────────────────────────

    @ViewBuilder
    private func dashboard(_ m: DashboardMetrics) -> some View {
        List {
            Section(header: Text("Momentum — last 7 days")) {
                deltaRow(label: "Placements", now: m.placements7d, prior: m.placementsPrior7d,
                         icon: "list.number", tint: .purple)
                deltaRow(label: "Active users", now: m.activeUsers7d, prior: m.activeUsersPrior7d,
                         icon: "person.2.fill", tint: .blue)
                deltaRow(label: "New users", now: m.newUsers7d, prior: m.newUsersPrior7d,
                         icon: "person.badge.plus", tint: .green)
            }

            Section(header: Text("Placements per day — last 14 days")) {
                Chart(m.dailyCounts, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Placements", entry.count)
                    )
                    .foregroundStyle(.purple.gradient)
                }
                .frame(height: 160)
                .padding(.vertical, 6)
            }

            // v2.1: all-time trend — weekly rankings (bars) vs cumulative (line).
            Section(header: Text("Rankings per week — since launch")) {
                Chart(m.weekly, id: \.week) { pt in
                    BarMark(
                        x: .value("Week", pt.week, unit: .weekOfYear),
                        y: .value("New", pt.newPlacements)
                    )
                    .foregroundStyle(Tier.s.color.opacity(0.85))
                    LineMark(
                        x: .value("Week", pt.week, unit: .weekOfYear),
                        y: .value("Cumulative", pt.cumPlacements)
                    )
                    .foregroundStyle(.primary)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
                }
                .frame(height: 190)
                .padding(.vertical, 6)
                Text("Bars: new rankings that week. Line: cumulative total (\(m.totalPlacements)).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // v2.1: cumulative rankers over time.
            Section(header: Text("Rankers — cumulative")) {
                Chart(m.weekly, id: \.week) { pt in
                    AreaMark(
                        x: .value("Week", pt.week, unit: .weekOfYear),
                        y: .value("Rankers", pt.cumUsers)
                    )
                    .foregroundStyle(Tier.a.color.opacity(0.25))
                    LineMark(
                        x: .value("Week", pt.week, unit: .weekOfYear),
                        y: .value("Rankers", pt.cumUsers)
                    )
                    .foregroundStyle(Tier.a.color)
                }
                .frame(height: 160)
                .padding(.vertical, 6)
                Text("Distinct people who have placed at least one ranking (\(m.totalUsers) total).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section(header: Text("Totals")) {
                plainRow("Active users (ever placed)", "\(m.totalUsers)", icon: "person.3.fill", tint: .blue)
                plainRow("Profiles", "\(m.profileCount)", icon: "person.crop.circle", tint: .indigo)
                plainRow("Foodie Pros", "\(m.prosCount)", icon: "star.fill", tint: .orange)
                plainRow("Placements", "\(m.totalPlacements)", icon: "list.number", tint: .purple)
                plainRow("Restaurants ranked", "\(m.restaurantsRanked)", icon: "fork.knife", tint: .green)
                plainRow("Catalog size", "\(store.restaurants.count)", icon: "books.vertical.fill", tint: .teal)
                plainRow("Catalog coverage",
                         store.restaurants.isEmpty ? "—"
                            : "\(Int(Double(m.restaurantsRanked) / Double(store.restaurants.count) * 100))%",
                         icon: "percent", tint: .mint)
                plainRow("Avg placements / user",
                         String(format: "%.1f", m.avgPlacementsPerUser),
                         icon: "chart.bar.fill", tint: .pink)
                plainRow("Median placements / user", "\(m.medianPlacementsPerUser)",
                         icon: "chart.bar", tint: .pink)
            }

            Section(header: Text("Tier mix — all placements")) {
                ForEach(Tier.allCases) { tier in
                    tierBar(tier: tier,
                            count: m.tierCounts[tier] ?? 0,
                            max: m.tierCounts.values.max() ?? 1,
                            total: m.totalPlacements)
                }
            }

            Section(header: Text("Users by rank")) {
                ForEach(FoodieRank.allCases) { rank in
                    HStack {
                        Text(rank.displayName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(rank.color, in: Capsule())
                        Spacer()
                        Text("\(m.usersByRank[rank] ?? 0)")
                            .font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
            }

            Section(
                header: Text("Top rankers"),
                footer: Text("Most active accounts by total placements.")
            ) {
                ForEach(m.topUsers, id: \.userID) { u in
                    HStack {
                        Text("\(u.userID.prefix(14))…")
                            .font(.subheadline.monospaced())
                        Spacer()
                        Text("\(u.count)")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text("last: \(u.lastActive.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Hottest restaurants — most votes")) {
                ForEach(m.hotRestaurants, id: \.restaurantID) { h in
                    HStack(spacing: 10) {
                        Text(h.consensus.label)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(h.consensus.color, in: RoundedRectangle(cornerRadius: 7))
                        Text(restaurantName(h.restaurantID))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(h.votes) votes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Live feed — latest placements")) {
                ForEach(m.recent, id: \.recordName) { p in
                    HStack(spacing: 10) {
                        Text(p.tier.label)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(p.tier.color, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(restaurantName(p.restaurantID))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("by \(p.userID.prefix(12))… · \(p.creationDate.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // ─── Row builders ────────────────────────────────────────────────

    @ViewBuilder
    private func deltaRow(label: String, now: Int, prior: Int, icon: String, tint: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(tint)
            Spacer()
            Text("\(now)")
                .font(.body.weight(.semibold)).monospacedDigit()
            deltaBadge(now: now, prior: prior)
        }
    }

    @ViewBuilder
    private func deltaBadge(now: Int, prior: Int) -> some View {
        let diff = now - prior
        let symbol = diff > 0 ? "arrow.up" : diff < 0 ? "arrow.down" : "minus"
        let color: Color = diff > 0 ? .green : diff < 0 ? .red : .secondary
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text(prior == 0 ? (diff == 0 ? "—" : "new") : "\(abs(diff))")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityLabel("Change vs prior week: \(diff)")
    }

    @ViewBuilder
    private func plainRow(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(tint)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private func tierBar(tier: Tier, count: Int, max: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            Text(tier.label)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 7))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(tier.color)
                        .frame(width: max > 0 ? geo.size.width * CGFloat(count) / CGFloat(max) : 0)
                }
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(total > 0 ? "\(Int(Double(count) / Double(total) * 100))%" : "—")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func restaurantName(_ id: UUID) -> String {
        store.restaurants.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func load() async {
        loading = true
        async let placementsTask = cloudKit.fetchAllPlacementsForAudit()
        async let profileTask = cloudKit.fetchProfileCount()
        async let prosTask = cloudKit.fetchProRequests()
        let (placements, profileCount, requests) = await (placementsTask, profileTask, prosTask)
        metrics = DashboardMetrics(
            placements: placements,
            profileCount: profileCount,
            prosCount: requests.approved.count
        )
        loading = false
    }
}

// ─── Metrics engine ──────────────────────────────────────────────────

/// Everything the dashboard shows, computed once from the placement
/// corpus. Pure value math — trivially testable.
struct DashboardMetrics {
    struct DayCount { let day: Date; let count: Int }
    struct TopUser { let userID: String; let count: Int; let lastActive: Date }
    struct HotRestaurant { let restaurantID: UUID; let votes: Int; let consensus: Tier }
    /// v2.1: one week of the all-time trend (new + cumulative).
    struct WeekPoint { let week: Date; let newPlacements: Int; let cumPlacements: Int; let newUsers: Int; let cumUsers: Int }

    let totalUsers: Int
    let totalPlacements: Int
    let restaurantsRanked: Int
    let profileCount: Int
    let prosCount: Int

    let placements7d: Int
    let placementsPrior7d: Int
    let activeUsers7d: Int
    let activeUsersPrior7d: Int
    let newUsers7d: Int
    let newUsersPrior7d: Int

    let dailyCounts: [DayCount]
    let weekly: [WeekPoint]
    let tierCounts: [Tier: Int]
    let usersByRank: [FoodieRank: Int]
    let topUsers: [TopUser]
    let hotRestaurants: [HotRestaurant]
    let recent: [AuditPlacement]

    let avgPlacementsPerUser: Double
    let medianPlacementsPerUser: Int

    init(placements: [AuditPlacement], profileCount: Int, prosCount: Int) {
        let now = Date()
        let cal = Calendar.current
        let d7 = now.addingTimeInterval(-7 * 86400)
        let d14 = now.addingTimeInterval(-14 * 86400)

        let byUser = Dictionary(grouping: placements, by: \.userID)
        let byRestaurant = Dictionary(grouping: placements, by: \.restaurantID)

        totalUsers = byUser.count
        totalPlacements = placements.count
        restaurantsRanked = byRestaurant.count
        self.profileCount = profileCount
        self.prosCount = prosCount

        // Momentum windows
        let last7 = placements.filter { $0.creationDate >= d7 }
        let prior7 = placements.filter { $0.creationDate >= d14 && $0.creationDate < d7 }
        placements7d = last7.count
        placementsPrior7d = prior7.count
        activeUsers7d = Set(last7.map(\.userID)).count
        activeUsersPrior7d = Set(prior7.map(\.userID)).count

        // "New user" = their FIRST-ever placement falls in the window.
        var firstSeen: [String: Date] = [:]
        for p in placements {
            if let existing = firstSeen[p.userID] {
                if p.creationDate < existing { firstSeen[p.userID] = p.creationDate }
            } else {
                firstSeen[p.userID] = p.creationDate
            }
        }
        newUsers7d = firstSeen.values.filter { $0 >= d7 }.count
        newUsersPrior7d = firstSeen.values.filter { $0 >= d14 && $0 < d7 }.count

        // 14-day daily chart (zero-filled so quiet days show as gaps)
        var buckets: [Date: Int] = [:]
        for offset in 0..<14 {
            let day = cal.startOfDay(for: now.addingTimeInterval(Double(-offset) * 86400))
            buckets[day] = 0
        }
        for p in placements where p.creationDate >= d14 {
            let day = cal.startOfDay(for: p.creationDate)
            if buckets[day] != nil { buckets[day]! += 1 }
        }
        dailyCounts = buckets.map { DayCount(day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }

        // Tier mix
        tierCounts = Dictionary(grouping: placements, by: \.tier).mapValues(\.count)

        // Rank ladder
        var ranks: [FoodieRank: Int] = [:]
        for (_, ps) in byUser {
            if let rank = FoodieRank.from(placementCount: ps.count) {
                ranks[rank, default: 0] += 1
            }
        }
        usersByRank = ranks

        // Top rankers
        topUsers = byUser
            .map { uid, ps in
                TopUser(userID: uid, count: ps.count,
                        lastActive: ps.map(\.creationDate).max() ?? .distantPast)
            }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }

        // Hottest restaurants + consensus
        hotRestaurants = byRestaurant
            .map { rid, votes in
                let avg = votes.map { Double($0.tier.score) }.reduce(0, +) / Double(votes.count)
                let consensus: Tier = avg >= 4.5 ? .s : avg >= 3.5 ? .a : avg >= 2.5 ? .b : avg >= 1.5 ? .c : .f
                return HotRestaurant(restaurantID: rid, votes: votes.count, consensus: consensus)
            }
            .sorted { $0.votes > $1.votes }
            .prefix(10)
            .map { $0 }

        // Live feed
        recent = placements.sorted { $0.creationDate > $1.creationDate }.prefix(12).map { $0 }

        // Engagement
        let counts = byUser.values.map(\.count).sorted()
        avgPlacementsPerUser = counts.isEmpty ? 0 : Double(counts.reduce(0, +)) / Double(counts.count)
        medianPlacementsPerUser = counts.isEmpty ? 0 : counts[counts.count / 2]

        // v2.1: all-time weekly trend (new + cumulative placements & rankers).
        func weekStart(_ d: Date) -> Date {
            cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
        }
        var newPByWeek: [Date: Int] = [:]
        for p in placements { newPByWeek[weekStart(p.creationDate), default: 0] += 1 }
        var newUByWeek: [Date: Int] = [:]
        for first in firstSeen.values { newUByWeek[weekStart(first), default: 0] += 1 }
        let allWeeks = Set(newPByWeek.keys).union(newUByWeek.keys).sorted()
        var cumP = 0, cumU = 0
        weekly = allWeeks.map { w in
            cumP += newPByWeek[w] ?? 0
            cumU += newUByWeek[w] ?? 0
            return WeekPoint(week: w,
                             newPlacements: newPByWeek[w] ?? 0, cumPlacements: cumP,
                             newUsers: newUByWeek[w] ?? 0, cumUsers: cumU)
        }
    }
}
