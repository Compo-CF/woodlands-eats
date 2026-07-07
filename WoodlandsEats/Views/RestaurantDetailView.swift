import SwiftUI
import MapKit
import PhotosUI
import UIKit

struct RestaurantDetailView: View {
    @Environment(TierListStore.self) private var tierStore
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(BlockListStore.self) private var blockList
    @Environment(VisitedStore.self) private var visitedStore
    let restaurant: Restaurant
    @State private var community: CommunityTier?
    @State private var dishPhotos: [DishPhoto] = []
    /// v1.3.1: multi-select photo upload. Max 5 per session to keep
    /// individual upload latency bounded; users can add more after.
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadingCount = 0          // 0 when idle
    @State private var uploadProgressTotal = 0     // for "Uploading X of Y"
    /// v1.3.1: track whether the initial photo fetch has completed, so
    /// the UI can show a skeleton placeholder instead of "No photos yet"
    /// during the loading window.
    @State private var photosLoaded = false
    @State private var closureCount = 0
    @State private var reportedByMe = false
    @State private var reportingPhotoID: String?
    @State private var reportConfirmation: String?
    @State private var showDeliveryPicker = false
    // v2.0 Feature 2: placement notes (the "why").
    @State private var myNote = ""
    @State private var savedNote = ""          // last value persisted to CloudKit
    @State private var savingNote = false
    @State private var communityNotes: [CommunityNote] = []
    @State private var notesLoaded = false
    @State private var reportingNoteName: String?

    private var noteDirty: Bool {
        myNote.trimmingCharacters(in: .whitespacesAndNewlines)
            != savedNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUploading: Bool { uploadingCount > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // v1.3.1: split closure indicator into two states.
                // Red "Permanently closed" banner only after admin
                // confirmation. Softer "X reports pending review"
                // hint when there are user reports but no admin verdict.
                if cloudKit.confirmedClosedIDs.contains(restaurant.id) {
                    closedBanner
                } else if closureCount > 0 {
                    pendingClosureNotice
                }
                header
                rateSection
                communitySection
                communityNotesSection
                photosSection
                if !restaurant.signatureDishes.isEmpty { dishesSection }
                aboutSection
                actionsSection
                closedReportButton
            }
            .padding()
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            community = await cloudKit.fetchCommunityTier(restaurantID: restaurant.id)
            dishPhotos = await cloudKit.fetchDishPhotos(
                restaurantID: restaurant.id,
                blockedUploaderIDs: blockList.blocked)
            photosLoaded = true
            let closure = await cloudKit.fetchClosureInfo(restaurantID: restaurant.id)
            closureCount = closure.count
            reportedByMe = closure.reportedByMe
            // v2.0 Feature 2: load my note + the community's notes.
            if let mine = await cloudKit.fetchMyNote(restaurantID: restaurant.id) {
                myNote = mine
                savedNote = mine
            }
            communityNotes = await cloudKit.fetchCommunityNotes(
                restaurantID: restaurant.id,
                blockedUserIDs: blockList.blocked)
            notesLoaded = true
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePicks(items) }
        }
        .alert("Thanks for the report",
               isPresented: Binding(
                get: { reportConfirmation != nil },
                set: { if !$0 { reportConfirmation = nil } }
               )) {
            Button("OK", role: .cancel) { reportConfirmation = nil }
        } message: {
            Text(reportConfirmation ?? "")
        }
        .sheet(isPresented: $showDeliveryPicker) {
            DeliveryPickerSheet { app in
                DeliveryPreference.set(app)
                showDeliveryPicker = false
                openDeliveryApp(app)
            }
            .presentationDetents([.height(280)])
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dish photos").font(.headline)
                Spacer()
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 5,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    if isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                            if uploadProgressTotal > 1 {
                                Text("\(uploadProgressTotal - uploadingCount + 1)/\(uploadProgressTotal)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Add", systemImage: "camera.fill").font(.subheadline)
                    }
                }
                .disabled(isUploading)
            }
            if !photosLoaded {
                // Skeleton row while the initial CloudKit fetch is in flight.
                // Prevents the "No photos yet" message flashing for ~500ms
                // on every detail-view open, which read as 'wonky'.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                                .frame(width: 130, height: 130)
                                .overlay(ProgressView().tint(.secondary))
                        }
                    }
                }
                .allowsHitTesting(false)
            } else if dishPhotos.isEmpty {
                Text("No photos yet — add the first one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dishPhotos) { photo in
                            if let ui = UIImage(data: photo.imageData) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 130, height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        if reportingPhotoID == photo.id {
                                            ProgressView()
                                                .padding(6)
                                                .background(.thinMaterial, in: Circle())
                                                .padding(4)
                                        }
                                    }
                                    .contextMenu {
                                        Button("Report photo", systemImage: "flag", role: .destructive) {
                                            Task { await reportPhoto(photo) }
                                        }
                                        if photo.submitterUserID != nil {
                                            Button("Block this uploader", systemImage: "hand.raised") {
                                                blockUploader(photo)
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                Text("Long-press a photo to report it or block the uploader.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func reportPhoto(_ photo: DishPhoto) async {
        reportingPhotoID = photo.id
        defer { reportingPhotoID = nil }
        if await cloudKit.reportPhoto(photoID: photo.id) {
            // Hide it locally right away — feels responsive, and the reporter
            // won't see the photo again on this device until they relaunch.
            dishPhotos.removeAll { $0.id == photo.id }
            reportConfirmation = "We'll review this photo within 24 hours."
        } else {
            reportConfirmation = "Couldn't submit the report. Please try again."
        }
    }

    private func blockUploader(_ photo: DishPhoto) {
        guard let uploader = photo.submitterUserID else { return }
        blockList.block(uploader)
        // Drop every photo from this uploader currently on screen.
        dishPhotos.removeAll { $0.submitterUserID == uploader }
        reportConfirmation = "You won't see photos from this uploader again. The administrator has been notified and will review."
        // App Review Guideline 1.2: blocking must also notify the developer of
        // the inappropriate content so the admin can investigate the user's
        // other uploads and remove them if warranted. Piggyback on the same
        // CloudKit PhotoReport flow that explicit reports use — admin's queue
        // doesn't need to distinguish reason; either signal triggers a review.
        Task {
            _ = await cloudKit.reportPhoto(photoID: photo.id)
        }
    }

    /// v1.3.1: upload N selected photos in sequence, with a running
    /// progress count so the PhotosPicker label can show "2/5" while
    /// uploads are in flight. Sequential (not parallel) so we don't
    /// hammer CloudKit + keep the optimistic-insert ordering stable.
    private func handlePicks(_ items: [PhotosPickerItem]) async {
        uploadProgressTotal = items.count
        uploadingCount = items.count
        defer {
            uploadingCount = 0
            uploadProgressTotal = 0
            pickerItems = []
        }
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let jpeg = Self.downscaledJPEG(from: raw) else {
                uploadingCount -= 1
                continue
            }
            if await cloudKit.uploadDishPhoto(restaurantID: restaurant.id, jpegData: jpeg, caption: nil) {
                // Optimistic insert; server-side IDs reconcile on next refetch.
                dishPhotos.insert(DishPhoto(id: UUID().uuidString, caption: nil,
                                            imageData: jpeg, submitterUserID: nil), at: 0)
            }
            uploadingCount -= 1
        }
        let fresh = await cloudKit.fetchDishPhotos(
            restaurantID: restaurant.id,
            blockedUploaderIDs: blockList.blocked)
        if !fresh.isEmpty { dishPhotos = fresh }
    }

    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1200,
                                       quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    // MARK: - Placement notes (v2.0 Feature 2)

    private func saveNote() async {
        savingNote = true
        defer { savingNote = false }
        let trimmed = myNote.trimmingCharacters(in: .whitespacesAndNewlines)
        await cloudKit.saveMyNote(restaurantID: restaurant.id, note: trimmed)
        myNote = trimmed
        savedNote = trimmed
    }

    private func reportNote(_ note: CommunityNote) async {
        reportingNoteName = note.placementRecordName
        defer { reportingNoteName = nil }
        if await cloudKit.reportNote(placementRecordName: note.placementRecordName) {
            communityNotes.removeAll { $0.id == note.id }
            reportConfirmation = "We'll review this note within 24 hours."
        } else {
            reportConfirmation = "Couldn't submit the report. Please try again."
        }
    }

    private func blockNoteAuthor(_ note: CommunityNote) {
        guard let author = note.authorUserID else { return }
        blockList.block(author)
        communityNotes.removeAll { $0.authorUserID == author }
        reportConfirmation = "You won't see notes from this user again. The administrator has been notified and will review."
        // App Review 1.2: blocking also notifies the developer of the content.
        Task { _ = await cloudKit.reportNote(placementRecordName: note.placementRecordName) }
    }

    private func place(_ tier: Tier) {
        tierStore.setTier(tier, for: restaurant.id)
        Task {
            await cloudKit.savePlacement(restaurantID: restaurant.id, tier: tier)
            community = await cloudKit.fetchCommunityTier(restaurantID: restaurant.id)
        }
    }

    private func clearPlacement() {
        tierStore.removeTier(for: restaurant.id)
        // The whole Placement record (note included) is deleted on the server,
        // so clear the local note state too.
        myNote = ""
        savedNote = ""
        Task {
            await cloudKit.removePlacement(restaurantID: restaurant.id)
            community = await cloudKit.fetchCommunityTier(restaurantID: restaurant.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(restaurant.name)
                .font(.title2.bold())
            Text(restaurant.cuisineSummary)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Label(restaurant.priceTier.displayName, systemImage: "dollarsign.circle")
                Label(restaurant.area.displayName, systemImage: "mappin.and.ellipse")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your tier")
                    .font(.headline)
                Spacer()
                if let t = tierStore.tier(for: restaurant.id) {
                    Text(t.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TierPicker(
                current: tierStore.tier(for: restaurant.id),
                onSelect: { place($0) },
                onClear: { clearPlacement() }
            )

            // v1.2: Visited toggle. Personal "I've been here" flag, local
            // only. Sits inside the tier card because it's the same
            // category of input (your personal take on this restaurant)
            // even though it's independent of the tier choice — you can
            // have visited but not ranked, or ranked but not visited.
            Divider()
            Button {
                visitedStore.toggle(restaurant.id)
                // v1.3: mirror to CloudKit so visits survive reinstall and
                // sync across devices on next launch. Fire-and-forget; local
                // state has already updated for instant UI feedback.
                Task { await cloudKit.saveVisitedList(visitedStore.visited) }
            } label: {
                HStack {
                    Image(systemName: visitedStore.isVisited(restaurant.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .foregroundStyle(visitedStore.isVisited(restaurant.id)
                                         ? .green
                                         : .secondary)
                        .imageScale(.large)
                    Text(visitedStore.isVisited(restaurant.id)
                         ? "You've been here"
                         : "Mark as visited")
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // v2.0 Feature 2: the "why". Only offered once a tier is placed —
            // a note without a ranking has nothing to explain. Shared publicly
            // on the community-notes list; moderated like every other UGC
            // surface (report + block + admin hide).
            if tierStore.tier(for: restaurant.id) != nil {
                Divider()
                noteEditor
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why this tier?")
                .font(.subheadline.weight(.semibold))
            Text("Add a one-line note. Shared with the community.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("e.g. Best brisket in the county", text: $myNote, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onChange(of: myNote) { _, new in
                    // Soft cap; keeps notes to a line and bounds moderation load.
                    if new.count > 140 { myNote = String(new.prefix(140)) }
                }
            HStack {
                Text("\(140 - myNote.count) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                if savingNote {
                    ProgressView()
                } else if noteDirty {
                    Button("Save note") { Task { await saveNote() } }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else if !savedNote.isEmpty {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    /// Community notes from other rankers (the viewer's own is in the editor).
    @ViewBuilder
    private var communityNotesSection: some View {
        if !communityNotes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What people say")
                    .font(.headline)
                ForEach(communityNotes) { note in
                    HStack(alignment: .top, spacing: 10) {
                        if let t = note.tier {
                            TierBadge(tier: t, size: 28)
                        }
                        Text(note.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if reportingNoteName == note.placementRecordName {
                            ProgressView()
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .contextMenu {
                        Button("Report note", systemImage: "flag", role: .destructive) {
                            Task { await reportNote(note) }
                        }
                        if note.authorUserID != nil {
                            Button("Block this user", systemImage: "hand.raised") {
                                blockNoteAuthor(note)
                            }
                        }
                    }
                }
                Text("Long-press a note to report it or block the author.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var communitySection: some View {
        if let community {
            HStack(spacing: 12) {
                TierBadge(tier: community.tier, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community tier")
                        .font(.headline)
                    Text("\(community.count) ranked · avg \(String(format: "%.1f", community.average))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var dishesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Known for")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(restaurant.signatureDishes, id: \.self) { dish in
                        Text(dish)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemBackground), in: .capsule)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.headline)
            Text(restaurant.description)
                .foregroundStyle(.secondary)
            Text(restaurant.address)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // v1.2: data-aware horizontal capsule row. Buttons render only when the
    // underlying Google Places signals say the action is available, so e.g.
    // a walk-in BBQ joint doesn't show a hollow "Reserve" pill that goes
    // nowhere useful. Directions always shows (we always have a coordinate);
    // everything else is conditional on the enriched seed fields.
    private var actionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionPill(systemImage: "car.fill", label: "Directions", tint: .blue) {
                    openInMaps()
                }
                if let tel = telURL {
                    actionPill(systemImage: "phone.fill", label: "Call", tint: .green) {
                        UIApplication.shared.open(tel)
                    }
                }
                if showReserveButton {
                    actionPill(systemImage: "fork.knife", label: "Reserve", tint: .orange) {
                        openReserve()
                    }
                }
                if showOrderButton {
                    actionPill(systemImage: "bag.fill", label: "Order", tint: .purple) {
                        handleOrderTap()
                    }
                }
                if let url = restaurant.websiteURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        pillContent(systemImage: "safari.fill", label: "Website", tint: .gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func actionPill(systemImage: String, label: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pillContent(systemImage: systemImage, label: label, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func pillContent(systemImage: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(label).fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint, in: Capsule())
    }

    private var showReserveButton: Bool {
        if restaurant.reservable == true { return true }
        // Some restaurants don't have the `reservable` boolean set but their
        // website is already an OpenTable / Resy listing — treat those as
        // bookable too.
        if let host = restaurant.websiteURL?.host?.lowercased() {
            if host.contains("opentable.com") || host.contains("resy.com") {
                return true
            }
        }
        return false
    }

    private var showOrderButton: Bool {
        restaurant.delivery == true || restaurant.takeout == true
    }

    private func openReserve() {
        // Prefer the direct booking URL if the website is already OpenTable
        // or Resy (most precise deeplink we have). Fall back to an OpenTable
        // search-by-name in the Woodlands metro.
        if let url = restaurant.websiteURL,
           let host = url.host?.lowercased(),
           host.contains("opentable.com") || host.contains("resy.com") {
            UIApplication.shared.open(url)
            return
        }
        let q = restaurant.name.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.opentable.com/s?term=\(q)&location=The+Woodlands+TX") {
            UIApplication.shared.open(url)
        }
    }

    private func handleOrderTap() {
        if let app = DeliveryPreference.current {
            openDeliveryApp(app)
        } else {
            showDeliveryPicker = true
        }
    }

    private func openDeliveryApp(_ app: DeliveryApp) {
        UIApplication.shared.open(
            app.searchURL(for: restaurant.name, city: "The Woodlands TX"))
    }

    private var telURL: URL? {
        guard let phone = restaurant.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel://\(digits)")
    }

    /// Soft notice when users have reported the spot closed but admin
    /// hasn't yet verified. Doesn't strike anything through; just lets
    /// the visitor know there's a question about the place's status.
    private var pendingClosureNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(.orange)
            Text(reportedByMe && closureCount == 1
                 ? "You reported this as possibly closed — pending review."
                 : "\(closureCount) \(closureCount == 1 ? "report" : "reports") of possible closure — pending review.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var closedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(reportedByMe && closureCount == 1
                 ? "You reported this permanently closed."
                 : "Permanently closed.")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }

    private var closedReportButton: some View {
        Button {
            Task {
                if reportedByMe {
                    _ = await cloudKit.unreportClosed(restaurantID: restaurant.id)
                } else {
                    _ = await cloudKit.reportClosed(restaurantID: restaurant.id)
                }
                let closure = await cloudKit.fetchClosureInfo(restaurantID: restaurant.id)
                closureCount = closure.count
                reportedByMe = closure.reportedByMe
                await cloudKit.refreshClosureCounts()
            }
        } label: {
            Label(reportedByMe ? "Undo \"permanently closed\" report" : "Report as permanently closed",
                  systemImage: reportedByMe ? "arrow.uturn.backward" : "exclamationmark.triangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(reportedByMe ? .gray : .red)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: restaurant.coordinate))
        item.name = restaurant.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
