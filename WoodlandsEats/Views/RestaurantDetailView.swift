import SwiftUI
import MapKit
import PhotosUI
import UIKit

struct RestaurantDetailView: View {
    @Environment(TierListStore.self) private var tierStore
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(BlockListStore.self) private var blockList
    let restaurant: Restaurant
    @State private var community: CommunityTier?
    @State private var dishPhotos: [DishPhoto] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var closureCount = 0
    @State private var reportedByMe = false
    @State private var reportingPhotoID: String?
    @State private var reportConfirmation: String?
    @State private var showDeliveryPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if closureCount > 0 { closedBanner }
                header
                rateSection
                communitySection
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
            let closure = await cloudKit.fetchClosureInfo(restaurantID: restaurant.id)
            closureCount = closure.count
            reportedByMe = closure.reportedByMe
        }
        .onChange(of: pickerItem) { _, item in
            Task { await handlePick(item) }
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
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Label("Add", systemImage: "camera.fill").font(.subheadline)
                    }
                }
                .disabled(isUploading)
            }
            if dishPhotos.isEmpty {
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

    private func handlePick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploading = true
        defer { isUploading = false; pickerItem = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let jpeg = Self.downscaledJPEG(from: raw) else { return }
        if await cloudKit.uploadDishPhoto(restaurantID: restaurant.id, jpegData: jpeg, caption: nil) {
            // Show it immediately; replace with the server list once it's queryable.
            dishPhotos.insert(DishPhoto(id: UUID().uuidString, caption: nil,
                                        imageData: jpeg, submitterUserID: nil), at: 0)
            let fresh = await cloudKit.fetchDishPhotos(
                restaurantID: restaurant.id,
                blockedUploaderIDs: blockList.blocked)
            if !fresh.isEmpty { dishPhotos = fresh }
        }
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

    private func place(_ tier: Tier) {
        tierStore.setTier(tier, for: restaurant.id)
        Task {
            await cloudKit.savePlacement(restaurantID: restaurant.id, tier: tier)
            community = await cloudKit.fetchCommunityTier(restaurantID: restaurant.id)
        }
    }

    private func clearPlacement() {
        tierStore.removeTier(for: restaurant.id)
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
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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

    private var closedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(reportedByMe && closureCount == 1
                 ? "You reported this permanently closed."
                 : "Reported permanently closed by \(closureCount).")
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
