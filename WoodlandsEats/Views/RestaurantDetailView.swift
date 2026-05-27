import SwiftUI
import MapKit
import PhotosUI
import UIKit

struct RestaurantDetailView: View {
    @Environment(TierListStore.self) private var tierStore
    @Environment(CloudKitService.self) private var cloudKit
    let restaurant: Restaurant
    @State private var community: CommunityTier?
    @State private var dishPhotos: [DishPhoto] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var closureCount = 0
    @State private var reportedByMe = false

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
            dishPhotos = await cloudKit.fetchDishPhotos(restaurantID: restaurant.id)
            let closure = await cloudKit.fetchClosureInfo(restaurantID: restaurant.id)
            closureCount = closure.count
            reportedByMe = closure.reportedByMe
        }
        .onChange(of: pickerItem) { _, item in
            Task { await handlePick(item) }
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
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
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
            dishPhotos.insert(DishPhoto(id: UUID().uuidString, caption: nil, imageData: jpeg), at: 0)
            let fresh = await cloudKit.fetchDishPhotos(restaurantID: restaurant.id)
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

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                openInMaps()
            } label: {
                Label("Directions", systemImage: "car.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                if let url = restaurant.websiteURL {
                    Link(destination: url) {
                        Label("Website", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if let tel = telURL {
                    Link(destination: tel) {
                        Label("Call", systemImage: "phone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
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
