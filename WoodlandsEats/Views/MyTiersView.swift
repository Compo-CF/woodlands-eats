import SwiftUI
import UniformTypeIdentifiers

/// v1.7 Feature A: Transferable wrapper that writes the rendered
/// tier-list card to a temp PNG file and shares that URL.
///
/// Why file-based instead of data-based: DataRepresentation exports
/// bytes tagged as image/png, which iOS routes correctly to some
/// share extensions (Messages, Mail, AirDrop) but NOT to "Save to
/// Photos" — that action only appears in the share sheet when the
/// shared item is a URL pointing to an image file on disk (iOS 17+
/// Photos share extension is picky about this). FileRepresentation
/// gives us both — file-based extensions plus Save to Photos.
///
/// Temp file lives under `FileManager.default.temporaryDirectory`;
/// iOS cleans up temp dirs automatically, no explicit removal needed.
struct ShareableTierImage: Transferable {
    let uiImage: UIImage

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { wrapper in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("MyTierList.png")
            if let data = wrapper.uiImage.pngData() {
                try? data.write(to: url, options: .atomic)
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName("MyTierList.png")
    }
}

struct MyTiersView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(TierListStore.self) private var tierStore
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.displayScale) private var displayScale
    /// v1.6: cached display name written by ProfileView when it loads
    /// or saves the user's FoodieProfile. Lets the share card show the
    /// user's name without an async CloudKit fetch on every render.
    @AppStorage("WoodlandsEats.cachedDisplayName") private var cachedDisplayName = ""
    /// v1.7 Feature C: cached CloudKit userRecordName for constructing
    /// the friend-share universal link.
    @AppStorage("WoodlandsEats.cachedUserID") private var cachedUserID = ""
    @State private var selected: Restaurant?
    /// v1.6: rendered share image (UIImage so we have access to pngData
    /// for the Transferable wrapper), generated when the user has at
    /// least one placement. Held in state so ShareLink can present it.
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if tierStore.rankedCount == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // v2.2: prominent share + invite CTAs (was toolbar-
                            // icon only). Sharing tier lists / inviting friends
                            // are the app's App-Referrer growth loop, so they
                            // get visible buttons, not a buried menu.
                            VStack(spacing: 10) {
                                Menu { shareMenuContent } label: {
                                    Label("Share my tier list", systemImage: "square.and.arrow.up")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.nightOut)
                                InviteFriendButton()
                            }
                            .padding(.bottom, 4)

                            ForEach(Tier.allCases) { tier in
                                TierRow(
                                    tier: tier,
                                    restaurants: tierStore.restaurants(in: tier, from: store.restaurants),
                                    onTap: { selected = $0 }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My Tiers")
            .toolbar { shareToolbar }
            .sheet(item: $selected) { r in
                NavigationStack {
                    RestaurantDetailView(restaurant: r)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear { rebuildShareImage() }
            .onChange(of: tierStore.rankedCount) { _, _ in rebuildShareImage() }
            .onChange(of: cachedDisplayName) { _, _ in rebuildShareImage() }
            // v1.7 Feature C: cache CloudKit userRecordName for the
            // friend-share URL. ProfileView.load() also writes this,
            // but first-launch users may build their tier list before
            // ever tapping Profile — so we ensure it's available here.
            .task {
                if cachedUserID.isEmpty,
                   let uid = await cloudKit.currentUserID(), !uid.isEmpty {
                    cachedUserID = uid
                }
            }
        }
    }

    /// v1.6/v1.7: Share toolbar — only visible when the user has at
    /// least one placement. Menu with two options:
    ///   - Share as image: ShareableTierCard rendered via ImageRenderer
    ///   - Share friend link: universal link to a read-only friend view
    @ToolbarContentBuilder
    private var shareToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if tierStore.rankedCount > 0 {
                Menu { shareMenuContent } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    /// The share options, shared by the toolbar menu and the prominent
    /// top-of-list button: share the rendered card image, and (if we have
    /// the user's ID) share the friend link.
    @ViewBuilder
    private var shareMenuContent: some View {
        if let image = shareImage {
            ShareLink(
                item: ShareableTierImage(uiImage: image),
                preview: SharePreview(
                    "My S-Tier Eats Tier List",
                    image: Image(uiImage: image)
                )
            ) {
                Label("Share as image", systemImage: "photo")
            }
        }
        if !cachedUserID.isEmpty,
           let url = URL(string: "https://compo-cf.github.io/woodlands-eats/tier/\(cachedUserID)") {
            ShareLink(
                item: url,
                subject: Text("My S-Tier Eats Tier List"),
                message: Text("Check out my Woodlands restaurant tier list:")
            ) {
                Label("Share friend link", systemImage: "link")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Build your tier list", systemImage: "list.number")
        } description: {
            Text("Open a restaurant from the Map or Browse tab and drop it into S, A, B, C, or F. Your ranked spots collect here.")
        }
    }

    /// Rebuilds the share image whenever ranked-count or display-name
    /// changes (and once on first appear). Runs on the main actor
    /// because ImageRenderer needs to walk the view tree.
    @MainActor
    private func rebuildShareImage() {
        guard tierStore.rankedCount > 0 else {
            shareImage = nil
            return
        }
        var byTier: [Tier: [Restaurant]] = [:]
        for tier in Tier.allCases {
            byTier[tier] = tierStore.restaurants(in: tier, from: store.restaurants)
        }
        let card = ShareableTierCard(
            displayName: cachedDisplayName,
            placementsByTier: byTier
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        shareImage = renderer.uiImage
    }
}

private struct TierRow: View {
    let tier: Tier
    let restaurants: [Restaurant]
    let onTap: (Restaurant) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tier.label)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 64)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 14))

            if restaurants.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(restaurants) { r in
                            Button {
                                onTap(r)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(r.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text(r.primaryCuisine.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 96, height: 52)
                                .padding(6)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
