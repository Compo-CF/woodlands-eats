import SwiftUI
import CoreLocation
// v1.7 Feature B: Sign in with Apple. AuthenticationServices provides
// SignInWithAppleButton (the Apple-styled button) and ASAuthorization
// types used by AppleSignInService.handleSignInResult.
import AuthenticationServices

/// Profile + Foodie Pro request, and (for admins) in-app approval.
/// Identity is the implicit iCloud account; the display name is self-entered.
/// Approval is an admin-owned `ProApproval` record (a user can't edit another
/// user's FoodieProfile in the public DB), so approving is admin-gated.
struct ProfileView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(TierListStore.self) private var tierStore
    /// v1.7 Feature B: SIWA service — layered on top of CloudKit identity.
    /// Provides the user's Apple-verified real name (one tap vs typing).
    @Environment(AppleSignInService.self) private var appleSignIn
    /// v1.7 Feature D: IAP store for the $1.99 ad-free upgrade.
    @Environment(PurchaseStore.self) private var purchases
    /// v1.9: push-notification opt-in service.
    @Environment(NotificationService.self) private var notifications
    /// v1.6: cached display name read by MyTiersView's share-card
    /// renderer so the user's name shows up without an async fetch.
    @AppStorage("WoodlandsEats.cachedDisplayName") private var cachedDisplayName = ""
    /// v1.7 Feature C: cached CloudKit userRecordName used by MyTiersView
    /// to construct the friend-share universal link.
    @AppStorage("WoodlandsEats.cachedUserID") private var cachedUserID = ""
    @State private var displayName = ""
    @State private var status = ""        // "" | "requested" | "approved"
    @State private var userID = ""
    @State private var loading = true
    @State private var saving = false
    @State private var isAdmin = false
    /// Phase 3 (Android migration): one-time full CloudKit → Firestore backfill.
    @State private var migrationRunning = false
    @State private var migrationResult: String?
    /// Part 2: one-time consensus-doc rebuild (Everyone-board optimization).
    @State private var consensusRunning = false
    @State private var consensusResult: String?
    /// Phase 4 read-cutover kill-switch (admin A/B). CloudKitService reads the
    /// same UserDefaults key to route per-restaurant community reads.
    @AppStorage("WoodlandsEats.useFirestoreReads") private var useFirestoreReads = false
    @State private var pending: [ProRequest] = []
    @State private var approvedPros: [ProRequest] = []
    @Environment(RestaurantStore.self) private var store
    /// v2.0 Feature 3: persistent follow graph.
    @Environment(FriendsStore.self) private var friendsStore
    /// v2.0: needed for account deletion (Guideline 5.1.1(v)) — wiped locally.
    @Environment(VisitedStore.self) private var visitedStore
    @Environment(BlockListStore.self) private var blockList
    @State private var showSuggest = false
    // v2.1: Friend Activity feed sheet.
    @State private var showFriendActivity = false
    // v2.0: account deletion (Guideline 5.1.1(v)).
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false
    @State private var accountDeleted = false
    @State private var pendingSuggestions: [Suggestion] = []
    @State private var approvingID: String?
    @State private var suggestionError: String?
    @State private var photoReports: [(report: PhotoReport, photo: DishPhoto?)] = []
    @State private var actingPhotoID: String?
    /// v2.0 Feature 2: admin queue of reported placement notes.
    @State private var noteReports: [PendingNoteReport] = []
    @State private var actingNoteName: String?
    /// v1.3.1: admin queue of restaurants with user closure reports
    /// awaiting a Confirm/Reject decision.
    @State private var pendingClosures: [(restaurant: Restaurant, count: Int)] = []
    @State private var actingClosureID: UUID?
    /// Closure reports whose restaurantID is no longer in the seed (e.g. a
    /// reseed changed the UUID) — they can't surface in the normal queue, so
    /// list them here with a one-tap Clear.
    @State private var orphanedClosures: [(id: UUID, count: Int)] = []
    /// v1.5: session-local set of restaurants the admin has just
    /// decided this session. CloudKit's TRUEPREDICATE queries can
    /// take 10-30s to surface freshly-written ClosureDecision records,
    /// so without this guard the just-decided restaurant briefly
    /// reappears in the pending queue on the next reload. Filtering
    /// here masks the propagation lag completely. Resets on view
    /// dismissal (in-memory @State, not persisted).
    @State private var recentlyDecidedClosureIDs: Set<UUID> = []
    @State private var showAbout = false
    @State private var showTierGuide = false
    @State private var showAppTour = false
    @State private var preferredDeliveryApp: DeliveryApp?
    // Build 22: a tap on Save name / Request Foodie Pro with an empty name
    // surfaces this alert string instead of being silently disabled. Apple
    // rejected build 19 under Guideline 2.1(a) because the reviewer read the
    // disabled state as "unresponsive button" — this makes every tap respond.
    @State private var requirementAlert: String?
    @FocusState private var nameFieldFocused: Bool

    private var nameEmpty: Bool {
        displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Foodie Pro requires a full name (first + last) so the admin can
    /// verify identity before approval. We check for at least two
    /// whitespace-separated parts, each ≥ 2 chars — catches "John"
    /// (too short, no last name) and "J Smith" (initial doesn't help
    /// verification) without being overly strict.
    private var isFullName: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        return parts.count >= 2 && parts.allSatisfy { $0.count >= 2 }
    }

    var body: some View {
        NavigationStack {
            Form {
                appleSignInSection
                Section(
                    header: Text("Display name"),
                    footer: Text("Shown with your reviews and on the Foodie Pro leaderboard.")
                ) {
                    TextField("Your name", text: $displayName)
                        .autocorrectionDisabled()
                        .focused($nameFieldFocused)
                    Button("Save name") {
                        if nameEmpty {
                            requirementAlert = "Please type a display name in the field above before saving."
                            nameFieldFocused = true
                        } else {
                            Task { await save(requestingPro: false) }
                        }
                    }
                    .disabled(saving)
                }

                Section(
                    header: Text("Foodie Pro"),
                    footer: Text("Foodie Pros' rankings power the \u{201C}Pros\u{201D} leaderboard on the Community tab. Requesting Foodie Pro requires your full name (first and last) in the Display name field above — the admin uses it to verify your identity before approval.")
                ) {
                    switch status {
                    case "approved":
                        Label("You're a Foodie Pro", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                    case "requested":
                        Label("Request pending approval", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    default:
                        Button {
                            if nameEmpty {
                                requirementAlert = "Please set a display name first — it appears next to your rankings on the Foodie Pro leaderboard. Type one in the Display name field above, then tap Request Foodie Pro."
                                nameFieldFocused = true
                            } else if !isFullName {
                                requirementAlert = "Foodie Pro requires your full name (first and last) so the admin can verify your identity before approval. Update your display name above with both names, then tap Request Foodie Pro."
                                nameFieldFocused = true
                            } else {
                                Task { await save(requestingPro: true) }
                            }
                        } label: {
                            Label("Request Foodie Pro", systemImage: "star")
                        }
                        .disabled(saving)
                    }
                }

                if let rank = FoodieRank.from(placementCount: tierStore.placements.count) {
                    Section(
                        header: Text("Your rank"),
                        footer: Text(rank == .tastemaker
                                     ? "Top tier reached. Keep ranking to maintain it."
                                     : "Earned by placing restaurants in tiers. Rank more spots to level up.")
                    ) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(rank.tintColor)
                                    .frame(width: 38, height: 38)
                                Image(systemName: rank.symbolName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(rank.color)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.displayName)
                                    .font(.headline)
                                    .foregroundStyle(rank.color)
                                Text("\(tierStore.placements.count) restaurants ranked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("My activity")) {
                    NavigationLink(destination: MyStatsView()) {
                        Label("My Stats", systemImage: "chart.bar.xaxis")
                    }
                }

                friendsSection

                notificationsSection

                Section(
                    header: Text("Help others"),
                    footer: Text("Spotted a place that's not in the app yet? Submit it and an admin will review.")
                ) {
                    Button {
                        showSuggest = true
                    } label: {
                        Label("Suggest a missing restaurant", systemImage: "plus.circle")
                    }
                }

                premiumSection

                if let app = preferredDeliveryApp {
                    Section(
                        header: Text("Preferences"),
                        footer: Text("Tap to forget this choice. We'll ask again the next time you tap Order on a restaurant.")
                    ) {
                        Button {
                            DeliveryPreference.clear()
                            preferredDeliveryApp = nil
                        } label: {
                            HStack {
                                Label("Delivery app", systemImage: "bag")
                                Spacer()
                                Text(app.displayName)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section(header: Text("About")) {
                    Button {
                        showAppTour = true
                    } label: {
                        Label("Show app tour", systemImage: "sparkles")
                    }
                    Button {
                        showTierGuide = true
                    } label: {
                        Label("Tier guide", systemImage: "questionmark.circle")
                    }
                    Button {
                        showAbout = true
                    } label: {
                        Label("About S-Tier Eats", systemImage: "info.circle")
                    }
                }

                if isAdmin {
                    // v1.8: admin tools. Both are NavigationLinks rather
                    // than inline so their CloudKit walks only fire when
                    // the admin taps in — Profile load stays fast. The
                    // Dashboard supersedes the old inline Stats card
                    // (momentum deltas, activity chart, tier mix, top
                    // rankers, hottest restaurants, live feed).
                    Section(header: Text("Admin tools")) {
                        NavigationLink(destination: AdminDashboardView()) {
                            Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                        }
                        NavigationLink(destination: AdminAuditView()) {
                            Label("Placement Audit", systemImage: "shield.checkered")
                        }
                        // Phase 3: full CloudKit → Firestore backfill for the
                        // Android cross-platform migration. Idempotent — safe to
                        // re-run; merge writes never clobber. Run once on device.
                        Button {
                            Task {
                                migrationRunning = true
                                migrationResult = nil
                                let counts = await cloudKit.runFullBackfill()
                                let total = counts.values.reduce(0, +)
                                migrationResult = total == 0
                                    ? "Nothing migrated — check admin status / rules."
                                    : "Migrated \(total) docs:\n" + counts
                                        .filter { $0.value > 0 }
                                        .sorted { $0.key < $1.key }
                                        .map { "  \($0.key): \($0.value)" }
                                        .joined(separator: "\n")
                                migrationRunning = false
                            }
                        } label: {
                            if migrationRunning {
                                Label { Text("Migrating…") } icon: { ProgressView() }
                            } else {
                                Label("Backfill to Firestore", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(migrationRunning)
                        if let migrationResult {
                            Text(migrationResult)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        // Phase 4: read-cutover kill-switch. Routes the detail-
                        // view community tier + dietary tags from Firestore
                        // instead of CloudKit so you can A/B the two on-device.
                        // Default OFF (CloudKit). Full board is Part 2.
                        Toggle(isOn: $useFirestoreReads) {
                            Label("Read from Firestore", systemImage: "arrow.down.circle")
                        }
                        Text("Community boards (Everyone/Pros/Friends) + detail-screen tier & dietary tags read from Firestore instead of CloudKit. Toggle on vs. off on the same restaurant/board — they should match. Admin A/B for the Android migration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Part 2: build the maintained consensus docs so the
                        // Everyone board reads ~1 doc/restaurant instead of
                        // scanning all placements. Run once; recompute-on-write
                        // keeps them fresh afterward.
                        Button {
                            Task {
                                consensusRunning = true
                                consensusResult = nil
                                let n = await FirebaseService.shared.rebuildAllConsensus()
                                consensusResult = "Built consensus for \(n) restaurants."
                                consensusRunning = false
                            }
                        } label: {
                            if consensusRunning {
                                Label { Text("Building…") } icon: { ProgressView() }
                            } else {
                                Label("Rebuild consensus docs", systemImage: "sum")
                            }
                        }
                        .disabled(consensusRunning)
                        if let consensusResult {
                            Text(consensusResult)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section(header: Text("Pending Pro requests")) {
                        if pending.isEmpty {
                            Text("No pending requests").foregroundStyle(.secondary)
                        } else {
                            ForEach(pending) { req in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(req.displayName.isEmpty ? "(no name)" : req.displayName)
                                            // v1.7 Feature B+: identity-
                                            // verified by Apple. Strong
                                            // signal for admin approval.
                                            if req.isAppleVerified {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundStyle(.green)
                                                    .accessibilityLabel("Apple-verified")
                                            }
                                        }
                                        Text(req.userID)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Approve") {
                                        Task { _ = await cloudKit.approvePro(userID: req.userID); await refreshAfterChange() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }
                            }
                        }
                    }
                    if !approvedPros.isEmpty {
                        Section(header: Text("Foodie Pros")) {
                            ForEach(approvedPros) { req in
                                HStack {
                                    Label(req.displayName.isEmpty ? "(no name)" : req.displayName,
                                          systemImage: "star.fill")
                                        .foregroundStyle(.orange)
                                    // v1.7 Feature B+: Apple-verified tells
                                    // the admin which Pros have a real-name
                                    // account vs. anonymous opt-out — fewer
                                    // identity checks to do manually.
                                    if req.isAppleVerified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                            .accessibilityLabel("Apple-verified")
                                    }
                                    Spacer()
                                    Button("Revoke") {
                                        Task { _ = await cloudKit.revokePro(userID: req.userID); await refreshAfterChange() }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }

                if isAdmin {
                    Section(header: Text("Pending restaurant suggestions")) {
                        if pendingSuggestions.isEmpty {
                            Text("No pending suggestions")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pendingSuggestions) { s in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name)
                                            .font(.headline)
                                        Text(s.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        if !s.cuisines.isEmpty {
                                            Text(s.cuisines.joined(separator: " · "))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if approvingID == s.id {
                                        ProgressView()
                                    } else {
                                        HStack(spacing: 6) {
                                            Button("Reject") {
                                                Task { await rejectOne(s) }
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                            Button("Approve") {
                                                Task { await approveOne(s) }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.green)
                                        }
                                    }
                                }
                            }
                        }
                        if let err = suggestionError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if isAdmin {
                    Section(
                        header: Text("Pending closure reports"),
                        footer: Text("Restaurants users have reported as permanently closed. Confirm to surface the closure on the Browse list and detail page. Reject if the report is wrong — the restaurant stays visible without a strikethrough.")
                    ) {
                        if pendingClosures.isEmpty {
                            Text("No pending closure reports")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pendingClosures, id: \.restaurant.id) { item in
                                closureReportRow(item)
                            }
                        }
                    }

                    if !orphanedClosures.isEmpty {
                        Section(
                            header: Text("Orphaned closure reports"),
                            footer: Text("Closure reports pointing at a restaurant ID that's no longer in the catalog (usually after a reseed changed the ID). They can't be actioned normally — clear them here.")
                        ) {
                            ForEach(orphanedClosures, id: \.id) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(item.count) \(item.count == 1 ? "report" : "reports")")
                                            .font(.subheadline)
                                        Text(item.id.uuidString)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    if actingClosureID == item.id {
                                        ProgressView()
                                    } else {
                                        Button("Clear") {
                                            Task {
                                                actingClosureID = item.id
                                                defer { actingClosureID = nil }
                                                if await cloudKit.clearClosureData(restaurantID: item.id) {
                                                    orphanedClosures.removeAll { $0.id == item.id }
                                                    store.confirmedClosedIDs = cloudKit.confirmedClosedIDs
                                                }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.orange)
                                    }
                                }
                            }
                        }
                    }
                }

                if isAdmin {
                    Section(header: Text("Photo reports")) {
                        if photoReports.isEmpty {
                            Text("No pending photo reports")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(photoReports, id: \.report.id) { item in
                                photoReportRow(item)
                            }
                        }
                    }
                }

                if isAdmin {
                    Section(
                        header: Text("Note reports"),
                        footer: Text("Placement notes users have flagged. Hide removes the note everywhere (the rating still counts). Keep dismisses the report.")
                    ) {
                        if noteReports.isEmpty {
                            Text("No pending note reports")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(noteReports) { item in
                                noteReportRow(item)
                            }
                        }
                    }
                }

                if !userID.isEmpty {
                    Section(
                        header: Text("Your iCloud ID"),
                        footer: Text("Used to attribute your rankings.")
                    ) {
                        Text(userID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // v2.0: account deletion (App Review Guideline 5.1.1(v)).
                // Because the app offers Sign in with Apple (account
                // creation), it must offer in-app account deletion.
                deleteAccountSection
            }
            .navigationTitle("Profile")
            .overlay {
                if loading { ProgressView() }
            }
            .task { await load() }
            .sheet(isPresented: $showSuggest) {
                SuggestRestaurantView()
            }
            .sheet(isPresented: $showAbout) {
                AboutSheetView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showTierGuide) {
                TierGuideView()
            }
            .sheet(isPresented: $showFriendActivity) {
                FriendActivityView()
            }
            .fullScreenCover(isPresented: $showAppTour) {
                AppTourWrapper(isPresented: $showAppTour)
            }
            .alert("Display name needed",
                   isPresented: Binding(
                    get: { requirementAlert != nil },
                    set: { if !$0 { requirementAlert = nil } }
                   )) {
                Button("OK", role: .cancel) { requirementAlert = nil }
            } message: {
                Text(requirementAlert ?? "")
            }
            // v2.0: two-step account deletion (Guideline 5.1.1(v)).
            .alert("Delete your account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your profile, all your rankings and notes, your visited list, your follows, your uploaded photos, and any submissions. This can't be undone.")
            }
            .alert("Account deleted", isPresented: $accountDeleted) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your account and all associated data have been removed.")
            }
        }
    }

    // MARK: - Account deletion (Guideline 5.1.1(v))

    @ViewBuilder
    private var deleteAccountSection: some View {
        Section(
            footer: Text("Permanently deletes your account and all associated data from S-Tier Eats.")
        ) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    if deletingAccount {
                        ProgressView()
                        Text("Deleting…")
                    } else {
                        Label("Delete Account", systemImage: "trash")
                    }
                    Spacer()
                }
            }
            .disabled(deletingAccount)
        }
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }

        // 1. Remove every CloudKit record the user created.
        _ = await cloudKit.deleteMyAccount()

        // 2. Sign out of Apple + wipe all local state.
        appleSignIn.signOut()
        tierStore.clearLocal()
        visitedStore.clearLocal()
        friendsStore.clearLocal()
        blockList.clearLocal()

        // 3. Clear cached identity + derived caches so the UI resets clean.
        let d = UserDefaults.standard
        for key in [
            "WoodlandsEats.cachedDisplayName",
            "WoodlandsEats.cachedUserID",
            "WoodlandsEats.communityCache.everyone",
            "WoodlandsEats.communityCache.pros",
            "WoodlandsEats.lastCelebratedRank",
        ] {
            d.removeObject(forKey: key)
        }

        // 4. Reset this screen's in-memory state.
        displayName = ""
        status = ""
        userID = ""
        pending = []
        approvedPros = []
        accountDeleted = true
    }

    /// v1.7 Feature B: Sign in with Apple section. Two states:
    ///   - Not signed in: tall Apple-styled button. On success captures
    ///     the user's real name (first sign-in only) and auto-fills
    ///     displayName if empty, then auto-saves.
    ///   - Signed in: green-check status + "Use Apple name" + sign-out.
    /// v2.0 Feature 3: the people the user follows. Each row opens that
    /// person's tier list; swipe to unfollow. Following happens from a
    /// friend's shared tier list (the Follow button in FriendTierView) —
    /// this section is where you review and manage who you follow, and it
    /// explains how to add more when empty.
    @ViewBuilder
    private var friendsSection: some View {
        Section(
            header: Text("Friends"),
            footer: Text(friendsStore.friends.isEmpty
                ? "Open a friend's shared tier list (they can share it from the My Tiers tab) and tap Follow. Their consensus shows up on the Community tab's Friends board."
                : "Tap a friend to see their tier list. Swipe to unfollow.")
        ) {
            if friendsStore.friends.isEmpty {
                Label("Not following anyone yet", systemImage: "person.2")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showFriendActivity = true
                } label: {
                    Label("Recent activity", systemImage: "clock.arrow.circlepath")
                }
                ForEach(friendsStore.friends) { friend in
                    NavigationLink(destination: FriendTierView(userID: friend.userID)) {
                        Label(friend.displayName.isEmpty ? "Foodie" : friend.displayName,
                              systemImage: "person.crop.circle")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Unfollow", role: .destructive) {
                            friendsStore.unfollow(userID: friend.userID, via: cloudKit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appleSignInSection: some View {
        Section(
            header: Text("Sign in with Apple"),
            footer: Text("Optional. Use your Apple-verified name for your profile in one tap instead of typing it. Your CloudKit ranking history stays the same either way.")
        ) {
            if appleSignIn.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with Apple")
                            .font(.subheadline.weight(.semibold))
                        if let name = appleSignIn.fullName, !name.isEmpty {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if let appleName = appleSignIn.fullName,
                   !appleName.isEmpty,
                   appleName != displayName {
                    Button("Use Apple name (\(appleName))") {
                        displayName = appleName
                        Task { await save(requestingPro: false) }
                    }
                    .disabled(saving)
                }
                Button("Sign out of Apple", role: .destructive) {
                    appleSignIn.signOut()
                    // v1.7 Feature B+: clear the verified badge on the
                    // community board by re-saving the profile with
                    // isAppleVerified=false (now that appleSignIn.isSignedIn
                    // is false). Only fire if there's already a profile;
                    // a never-saved user shouldn't get an empty profile
                    // written just from a sign-out.
                    if !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { await save(requestingPro: false) }
                    }
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    appleSignIn.handleSignInResult(result)
                    if let appleName = appleSignIn.fullName,
                       !appleName.isEmpty,
                       displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                        displayName = appleName
                        Task { await save(requestingPro: false) }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            }
        }
    }

    /// v1.7 Feature D: Premium / Remove Ads section. Three states:
    ///   - Already purchased: green checkmark "Ad-free" badge.
    ///   - Product loaded: "Remove Ads — $1.99" + "Restore Purchases".
    ///   - Product loading: spinner.
    @ViewBuilder
    private var premiumSection: some View {
        Section(
            header: Text("Premium"),
            footer: Text(purchases.isAdFree
                ? "Thanks for supporting S-Tier Eats — banner ads are turned off on this device and any device signed in with the same Apple ID."
                : "One-time purchase. Permanently hides the banner ad on the Map and Browse tabs.")
        ) {
            if purchases.isAdFree {
                Label("Ad-free", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
            } else if let product = purchases.adFreeProduct {
                Button {
                    Task { await purchases.purchaseAdFree() }
                } label: {
                    HStack {
                        Label("Remove Ads", systemImage: "rectangle.slash")
                        Spacer()
                        Text(product.displayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(purchases.isPurchasing)
                Button("Restore Purchases") {
                    Task { await purchases.restorePurchases() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    Image(systemName: "rectangle.slash")
                    Text("Remove Ads")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    /// v1.9: push-notification opt-in. A single toggle that requests
    /// permission on enable and registers/removes CloudKit subscriptions.
    /// If the OS has denied notifications, the toggle is disabled and we
    /// point the user to Settings (can't re-prompt once denied).
    @ViewBuilder
    private var notificationsSection: some View {
        Section(
            header: Text("Notifications"),
            footer: Text(notifications.authorization == .denied
                ? "Notifications are turned off for S-Tier Eats in iOS Settings. Enable them there to get alerts."
                : "Get a heads-up when a new restaurant is added to your area, or when you're approved as a Foodie Pro.")
        ) {
            Toggle(isOn: Binding(
                get: { notifications.enabled && notifications.authorization != .denied },
                set: { on in Task { await notifications.setEnabled(on, currentUserID: userID) } }
            )) {
                Label("New restaurant & status alerts", systemImage: "bell.badge")
            }
            .disabled(notifications.authorization == .denied)
        }
    }

    private func load() async {
        loading = true
        preferredDeliveryApp = DeliveryPreference.current
        userID = await cloudKit.currentUserID() ?? ""
        // v1.6: mirror userID to AppStorage so MyTiersView's friend-
        // share URL can read it synchronously.
        cachedUserID = userID
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        // v1.6: mirror displayName to AppStorage so MyTiersView's
        // share-card renderer can read it synchronously.
        cachedDisplayName = profile.displayName
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        isAdmin = await cloudKit.isAdmin()
        if isAdmin {
            await reloadAdmin()
            pendingSuggestions = await cloudKit.fetchPendingSuggestions()
            await reloadPhotoReports()
            await reloadClosureReports()
            await reloadNoteReports()
        }
        loading = false
    }

    /// v1.3.1: build the admin closure-report queue. fetchPendingClosureReports
    /// returns (restaurantID, count) — we hydrate each with the actual
    /// Restaurant from the store so the admin can see name + address.
    /// Drops any restaurant IDs that no longer exist in the catalog
    /// (could happen if the restaurant was removed in a future seed pass
    /// while reports lingered in CloudKit).
    private func reloadClosureReports() async {
        let raw = await cloudKit.fetchPendingClosureReports()
        let byID = Dictionary(store.restaurants.map { ($0.id, $0) },
                              uniquingKeysWith: { _, latest in latest })
        pendingClosures = raw.compactMap { item in
            // v1.5: drop anything the admin decided earlier in this
            // session — masks CloudKit's eventual-consistency window
            // (ClosureDecision records can take ~30s to appear in
            // TRUEPREDICATE queries even after a successful write).
            guard !recentlyDecidedClosureIDs.contains(item.restaurantID) else { return nil }
            guard let r = byID[item.restaurantID] else { return nil }
            return (r, item.count)
        }
        // Orphaned: any restaurant with closure reports whose UUID is no longer
        // in the current seed (fetchPendingClosureReports refreshed closureCounts).
        // These can't render a normal row, so surface them for cleanup.
        orphanedClosures = cloudKit.closureCounts
            .filter { $0.value > 0 && byID[$0.key] == nil && !recentlyDecidedClosureIDs.contains($0.key) }
            .map { (id: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private func closureReportRow(_ item: (restaurant: Restaurant, count: Int)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.restaurant.name)
                    .font(.headline)
                Text(item.restaurant.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(item.count) \(item.count == 1 ? "report" : "reports")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if actingClosureID == item.restaurant.id {
                ProgressView()
            } else {
                HStack(spacing: 6) {
                    Button("Reject") {
                        Task { await decideClosure(item.restaurant.id, confirm: false) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    Button("Confirm") {
                        Task { await decideClosure(item.restaurant.id, confirm: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }

    private func decideClosure(_ restaurantID: UUID, confirm: Bool) async {
        actingClosureID = restaurantID
        defer { actingClosureID = nil }
        let ok = confirm
            ? await cloudKit.confirmClosed(restaurantID: restaurantID)
            : await cloudKit.markOpen(restaurantID: restaurantID)
        if ok {
            pendingClosures.removeAll { $0.restaurant.id == restaurantID }
            recentlyDecidedClosureIDs.insert(restaurantID)
            // Refresh the global closure caches so the strikethrough +
            // banner update immediately across the app, and mirror the
            // confirmed set into the store so Map + Browse drop the
            // restaurant from discovery in this same render pass.
            await cloudKit.refreshClosureCounts()
            store.confirmedClosedIDs = cloudKit.confirmedClosedIDs
        }
    }

    private func reloadPhotoReports() async {
        let reports = await cloudKit.fetchPendingPhotoReports()
        var hydrated: [(report: PhotoReport, photo: DishPhoto?)] = []
        for r in reports {
            let photo = await cloudKit.fetchPhoto(photoID: r.photoID)
            hydrated.append((r, photo))
        }
        photoReports = hydrated
    }

    @ViewBuilder
    private func photoReportRow(_ item: (report: PhotoReport, photo: DishPhoto?)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let data = item.photo?.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Reported photo").font(.subheadline.weight(.semibold))
                if let uid = item.photo?.submitterUserID {
                    Text("Uploader: \(uid.prefix(12))…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if actingPhotoID == item.report.photoID {
                    ProgressView().padding(.top, 2)
                } else {
                    HStack(spacing: 6) {
                        Button("Keep") {
                            Task { await actOnPhoto(item.report.photoID, hide: false) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                        Button("Hide", role: .destructive) {
                            Task { await actOnPhoto(item.report.photoID, hide: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actOnPhoto(_ photoID: String, hide: Bool) async {
        actingPhotoID = photoID
        defer { actingPhotoID = nil }
        let ok = hide
            ? await cloudKit.hidePhoto(photoID: photoID)
            : await cloudKit.approvePhoto(photoID: photoID)
        if ok {
            photoReports.removeAll { $0.report.photoID == photoID }
        }
    }

    private func reloadNoteReports() async {
        noteReports = await cloudKit.fetchPendingNoteReports()
    }

    @ViewBuilder
    private func noteReportRow(_ item: PendingNoteReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\u{201C}\(item.text)\u{201D}")
                .font(.subheadline)
            if let uid = item.authorUserID {
                Text("Author: \(uid.prefix(12))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if actingNoteName == item.placementRecordName {
                ProgressView().padding(.top, 2)
            } else {
                HStack(spacing: 6) {
                    Button("Keep") {
                        Task { await actOnNote(item.placementRecordName, hide: false) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    Button("Hide", role: .destructive) {
                        Task { await actOnNote(item.placementRecordName, hide: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actOnNote(_ placementName: String, hide: Bool) async {
        actingNoteName = placementName
        defer { actingNoteName = nil }
        // "Keep" just clears it from this session's queue — there's no
        // approved-marker for notes; a re-report would resurface it, which
        // is the desired behavior for text that's borderline.
        if hide {
            _ = await cloudKit.hideNote(placementRecordName: placementName)
        }
        noteReports.removeAll { $0.placementRecordName == placementName }
    }

    private func rejectOne(_ s: Suggestion) async {
        approvingID = s.id
        suggestionError = nil
        defer { approvingID = nil }
        if await cloudKit.rejectSuggestion(s) {
            pendingSuggestions.removeAll { $0.id == s.id }
        } else {
            suggestionError = "Couldn't reject \(s.name)."
        }
    }

    private func approveOne(_ s: Suggestion) async {
        approvingID = s.id
        suggestionError = nil
        defer { approvingID = nil }
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(s.address)
            guard let loc = placemarks.first?.location else {
                suggestionError = "Couldn't locate \(s.name) — address didn't resolve."
                return
            }
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            guard ServiceArea.contains(lat: lat, lon: lon) else {
                suggestionError = "\(s.name): geocoded outside the S-Tier Eats service area."
                return
            }
            let ok = await cloudKit.approveSuggestion(s, latitude: lat, longitude: lon)
            if ok {
                pendingSuggestions.removeAll { $0.id == s.id }
                await store.refreshLive(via: cloudKit)
            } else {
                suggestionError = "Couldn't save approval for \(s.name)."
            }
        } catch {
            suggestionError = "Geocoding failed for \(s.name): \(error.localizedDescription)"
        }
    }

    private func reloadAdmin() async {
        let requests = await cloudKit.fetchProRequests()
        pending = requests.pending
        approvedPros = requests.approved
    }

    /// After an approve/revoke, refresh both the admin lists and my own status
    /// (so approving yourself flips the top section to "You're a Foodie Pro").
    private func refreshAfterChange() async {
        let profile = await cloudKit.fetchMyProfile()
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        await reloadAdmin()
    }

    private func save(requestingPro: Bool) async {
        saving = true
        // v1.7 Feature B+: pass the current SIWA state so the FoodieProfile
        // record reflects whether the user has Apple-verified their
        // identity. The Pros / Community leaderboard reads this flag back
        // to overlay an Apple-verified checkmark next to verified Pros.
        _ = await cloudKit.saveProfile(
            displayName: displayName,
            requestingPro: requestingPro,
            isAppleVerified: appleSignIn.isSignedIn
        )
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        // v1.6: keep the share-card cache in sync with the saved name.
        cachedDisplayName = profile.displayName
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        saving = false
    }
}
