import SwiftUI
import CoreLocation

/// Profile + Foodie Pro request, and (for admins) in-app approval.
/// Identity is the implicit iCloud account; the display name is self-entered.
/// Approval is an admin-owned `ProApproval` record (a user can't edit another
/// user's FoodieProfile in the public DB), so approving is admin-gated.
struct ProfileView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @State private var displayName = ""
    @State private var status = ""        // "" | "requested" | "approved"
    @State private var userID = ""
    @State private var loading = true
    @State private var saving = false
    @State private var isAdmin = false
    @State private var pending: [ProRequest] = []
    @State private var approvedPros: [ProRequest] = []
    @Environment(RestaurantStore.self) private var store
    @State private var showSuggest = false
    @State private var pendingSuggestions: [Suggestion] = []
    @State private var approvingID: String?
    @State private var suggestionError: String?
    @State private var photoReports: [(report: PhotoReport, photo: DishPhoto?)] = []
    @State private var actingPhotoID: String?
    /// v1.3.1: admin queue of restaurants with user closure reports
    /// awaiting a Confirm/Reject decision.
    @State private var pendingClosures: [(restaurant: Restaurant, count: Int)] = []
    @State private var actingClosureID: UUID?
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

                Section(header: Text("My activity")) {
                    NavigationLink(destination: MyStatsView()) {
                        Label("My Stats", systemImage: "chart.bar.xaxis")
                    }
                }

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

                Section(
                    header: Text("Support S-Tier Eats"),
                    footer: Text("S-Tier Eats is free. If you've enjoyed using it, a small tip keeps the lights on and funds new features.")
                ) {
                    Link(destination: URL(string: "https://ko-fi.com/subtlefoodie")!) {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy me a coffee")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        .foregroundStyle(.white)
                    }
                    .listRowBackground(Color.red)
                }

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
                    Section(header: Text("Pending Pro requests")) {
                        if pending.isEmpty {
                            Text("No pending requests").foregroundStyle(.secondary)
                        } else {
                            ForEach(pending) { req in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(req.displayName.isEmpty ? "(no name)" : req.displayName)
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
        }
    }

    private func load() async {
        loading = true
        preferredDeliveryApp = DeliveryPreference.current
        userID = await cloudKit.currentUserID() ?? ""
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        isAdmin = await cloudKit.isAdmin()
        if isAdmin {
            await reloadAdmin()
            pendingSuggestions = await cloudKit.fetchPendingSuggestions()
            await reloadPhotoReports()
            await reloadClosureReports()
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
            guard let r = byID[item.restaurantID] else { return nil }
            return (r, item.count)
        }
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
            // Refresh the global closure caches so the strikethrough +
            // banner update immediately across the app.
            await cloudKit.refreshClosureCounts()
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
        _ = await cloudKit.saveProfile(displayName: displayName, requestingPro: requestingPro)
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        saving = false
    }
}
