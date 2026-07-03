import SwiftUI

/// v1.8 (integrity audit): admin-only screen that answers "who and what
/// should I check?" and lets the admin remediate on the spot.
///
/// Three tabs:
///   Users        — accounts ranked by suspicion score; drill in for
///                  their full placement history + Ban / per-rating
///                  Exclude actions
///   Restaurants  — places ranked by suspicion score (names resolved
///                  from the local catalog); drill in for every vote
///                  + Exclude-rating / Ban-voter actions
///   Remedied     — active bans + excluded ratings, with Undo
///
/// Remediation is implemented as admin-owned AdminExclusion records
/// (CloudKit won't let the admin delete another user's Placement).
/// Banned users keep their local My Tiers; their votes just stop
/// counting in every community aggregate, for everyone.
struct AdminAuditView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store

    @State private var report: AuditReport?
    @State private var loading = false
    @State private var tab: AuditTab = .users

    private let audit = AuditService()

    enum AuditTab: String, CaseIterable, Identifiable {
        case users = "Users"
        case restaurants = "Restaurants"
        case remedied = "Remedied"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("Paging all placements…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report {
                VStack(spacing: 0) {
                    Picker("View", selection: $tab) {
                        ForEach(AuditTab.allCases) { t in Text(t.rawValue).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    switch tab {
                    case .users: usersList(report)
                    case .restaurants: restaurantsList(report)
                    case .remedied: remediedList
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Run an audit", systemImage: "shield.checkered")
                } description: {
                    Text("Tap refresh to page all Placement records and rank suspicious users and restaurants.")
                }
            }
        }
        .navigationTitle("Placement Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await runAudit(force: true) }
                } label: { Image(systemName: "arrow.clockwise") }
                .disabled(loading)
            }
        }
        .task { if report == nil { await runAudit(force: false) } }
    }

    // ─── Users tab ───────────────────────────────────────────────────

    @ViewBuilder
    private func usersList(_ report: AuditReport) -> some View {
        List {
            summarySection(report)
            if report.suspiciousUsers.isEmpty {
                Section {
                    Label("No suspicious users flagged.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Section(
                    header: Text("\(report.suspiciousUsers.count) flagged — highest risk first"),
                    footer: Text("Score guide: 40+ check today · 20-39 check this week · under 20 informational.")
                ) {
                    ForEach(report.suspiciousUsers) { user in
                        NavigationLink {
                            UserAuditDetailView(user: user, onChange: reload)
                        } label: {
                            userRow(user)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func userRow(_ user: UserAudit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortID(user.userID))
                    .font(.subheadline.monospaced().weight(.semibold))
                if cloudKit.bannedUserIDs.contains(user.userID) {
                    Text("BANNED")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                scoreBadge(user.score)
            }
            Text("\(user.placements.count) placement\(user.placements.count == 1 ? "" : "s") · \(user.distributionString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let first = user.reasons.first {
                Text(first)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // ─── Restaurants tab ─────────────────────────────────────────────

    @ViewBuilder
    private func restaurantsList(_ report: AuditReport) -> some View {
        List {
            summarySection(report)
            if report.suspiciousRestaurants.isEmpty {
                Section {
                    Label("No suspicious restaurants flagged.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Section(header: Text("\(report.suspiciousRestaurants.count) flagged — highest risk first")) {
                    ForEach(report.suspiciousRestaurants) { r in
                        NavigationLink {
                            RestaurantAuditDetailView(restaurantAudit: r, onChange: reload)
                        } label: {
                            restaurantRow(r)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func restaurantRow(_ r: RestaurantAudit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(restaurantName(r.restaurantID))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                scoreBadge(r.score)
            }
            Text("\(r.votes.count) vote\(r.votes.count == 1 ? "" : "s") · \(r.distributionString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let first = r.reasons.first {
                Text(first)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // ─── Remedied tab ────────────────────────────────────────────────

    @ViewBuilder
    private var remediedList: some View {
        List {
            Section(
                header: Text("Banned users (\(cloudKit.bannedUserIDs.count))"),
                footer: Text("A banned user keeps their own My Tiers locally — their votes just stop counting in every community aggregate.")
            ) {
                if cloudKit.bannedUserIDs.isEmpty {
                    Text("No banned users").foregroundStyle(.secondary)
                } else {
                    ForEach(cloudKit.bannedUserIDs.sorted(), id: \.self) { uid in
                        HStack {
                            Text(shortID(uid)).font(.subheadline.monospaced())
                            Spacer()
                            Button("Unban") {
                                Task { _ = await cloudKit.unbanUser(userID: uid); await reload() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section(header: Text("Excluded ratings (\(cloudKit.excludedPlacementNames.count))")) {
                if cloudKit.excludedPlacementNames.isEmpty {
                    Text("No excluded ratings").foregroundStyle(.secondary)
                } else {
                    ForEach(cloudKit.excludedPlacementNames.sorted(), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(restaurantName(fromPlacementRecordName: name))
                                .font(.subheadline.weight(.medium))
                            HStack {
                                Text("by \(shortID(ownerID(fromPlacementRecordName: name) ?? "?"))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore") {
                                    Task { _ = await cloudKit.restorePlacement(recordName: name); await reload() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // ─── Shared bits ─────────────────────────────────────────────────

    @ViewBuilder
    private func summarySection(_ report: AuditReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.totalPlacements) placements · \(report.totalUsers) users · \(report.totalRestaurantsRanked) restaurants ranked")
                    .font(.caption)
                Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func scoreBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(score >= 40 ? Color.red : score >= 20 ? .orange : .yellow, in: Capsule())
            .foregroundStyle(score >= 20 ? .white : .black)
    }

    private func restaurantName(_ id: UUID) -> String {
        store.restaurants.first(where: { $0.id == id })?.name ?? "Unknown (\(id.uuidString.prefix(8))…)"
    }

    private func restaurantName(fromPlacementRecordName name: String) -> String {
        guard name.count >= 36, let rid = UUID(uuidString: String(name.suffix(36))) else { return "Unknown rating" }
        return restaurantName(rid)
    }

    private func ownerID(fromPlacementRecordName name: String) -> String? {
        let prefix = "placement_"
        guard name.hasPrefix(prefix), name.count > prefix.count + 37 else { return nil }
        return String(name.dropFirst(prefix.count).dropLast(37))
    }

    private func shortID(_ uid: String) -> String {
        uid.count > 14 ? "\(uid.prefix(14))…" : uid
    }

    private func runAudit(force: Bool) async {
        loading = true
        await cloudKit.loadExclusionsIfNeeded(force: force)
        let placements = await cloudKit.fetchAllPlacementsForAudit()
        report = audit.analyze(placements)
        loading = false
    }

    /// Passed into detail views so a ban/exclude refreshes this list.
    private func reload() async {
        await runAudit(force: true)
    }
}

// ─── User drill-down ─────────────────────────────────────────────────

/// Full evidence for one flagged user: reasons, then every placement
/// with restaurant name + tier + date. Actions: Ban / Unban the user,
/// or exclude individual ratings.
struct UserAuditDetailView: View {
    let user: UserAudit
    var onChange: () async -> Void

    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @State private var working = false
    @State private var confirmBan = false

    private var isBanned: Bool { cloudKit.bannedUserIDs.contains(user.userID) }

    var body: some View {
        List {
            Section(header: Text("Why flagged (score \(user.score))")) {
                ForEach(user.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if isBanned {
                    Button {
                        Task { working = true; _ = await cloudKit.unbanUser(userID: user.userID); await onChange(); working = false }
                    } label: {
                        Label("Unban user (votes count again)", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(working)
                } else {
                    Button(role: .destructive) {
                        confirmBan = true
                    } label: {
                        Label("Ban user (exclude all their ratings)", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .disabled(working)
                }
            } footer: {
                Text("User ID: \(user.userID)")
                    .font(.caption2.monospaced())
            }

            Section(header: Text("All placements (\(user.placements.count))")) {
                ForEach(user.placements) { p in
                    placementRow(p)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("User \(String(user.userID.prefix(10)))…")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Ban this user? All \(user.placements.count) of their ratings stop counting in community tiers for everyone. You can unban later.",
            isPresented: $confirmBan, titleVisibility: .visible
        ) {
            Button("Ban user", role: .destructive) {
                Task { working = true; _ = await cloudKit.banUser(userID: user.userID); await onChange(); working = false }
            }
        }
    }

    @ViewBuilder
    private func placementRow(_ p: AuditPlacement) -> some View {
        let excluded = cloudKit.excludedPlacementNames.contains(p.recordName)
        HStack(spacing: 10) {
            Text(p.tier.label)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(p.tier.color, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.restaurants.first(where: { $0.id == p.restaurantID })?.name
                     ?? "Unknown (\(p.restaurantID.uuidString.prefix(8))…)")
                    .font(.subheadline)
                    .strikethrough(excluded)
                Text(p.creationDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if excluded {
                Button("Restore") {
                    Task { _ = await cloudKit.restorePlacement(recordName: p.recordName); await onChange() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                Button("Exclude") {
                    Task { _ = await cloudKit.excludePlacement(recordName: p.recordName); await onChange() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

// ─── Restaurant drill-down ───────────────────────────────────────────

/// Full evidence for one flagged restaurant: reasons, then every vote
/// with the voter's ID + tier + date. Actions: exclude individual
/// ratings, or jump straight to banning a voter.
struct RestaurantAuditDetailView: View {
    let restaurantAudit: RestaurantAudit
    var onChange: () async -> Void

    @Environment(CloudKitService.self) private var cloudKit
    @Environment(RestaurantStore.self) private var store
    @State private var banTarget: String?

    private var name: String {
        store.restaurants.first(where: { $0.id == restaurantAudit.restaurantID })?.name
            ?? "Unknown restaurant"
    }

    var body: some View {
        List {
            Section(header: Text("Why flagged (score \(restaurantAudit.score))")) {
                ForEach(restaurantAudit.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section(
                header: Text("All votes (\(restaurantAudit.votes.count)) · \(restaurantAudit.distributionString)"),
                footer: Text("Exclude masks one rating from community tiers. Ban voter excludes ALL that account's ratings app-wide.")
            ) {
                ForEach(restaurantAudit.votes) { vote in
                    voteRow(vote)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Ban this voter? All of their ratings across the app stop counting. You can unban later.",
            isPresented: Binding(get: { banTarget != nil }, set: { if !$0 { banTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ban voter", role: .destructive) {
                if let uid = banTarget {
                    Task { _ = await cloudKit.banUser(userID: uid); await onChange() }
                }
                banTarget = nil
            }
        }
    }

    @ViewBuilder
    private func voteRow(_ p: AuditPlacement) -> some View {
        let excluded = cloudKit.excludedPlacementNames.contains(p.recordName)
        let voterBanned = cloudKit.bannedUserIDs.contains(p.userID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(p.tier.label)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(p.tier.color, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(p.userID.prefix(14))…")
                            .font(.caption.monospaced())
                            .strikethrough(excluded || voterBanned)
                        if voterBanned {
                            Text("BANNED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(p.creationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                if excluded {
                    Button("Restore rating") {
                        Task { _ = await cloudKit.restorePlacement(recordName: p.recordName); await onChange() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                } else {
                    Button("Exclude rating") {
                        Task { _ = await cloudKit.excludePlacement(recordName: p.recordName); await onChange() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                if !voterBanned {
                    Button("Ban voter") { banTarget = p.userID }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}
