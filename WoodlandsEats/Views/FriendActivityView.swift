import SwiftUI

/// v2.1: "Friend Activity" — a reverse-chronological feed of what the people
/// you follow have ranked recently. Pull-based (no push): opened explicitly
/// from the Community → Friends board and from Profile → Friends. Reuses the
/// existing follow graph + placement data; tapping a row opens the restaurant.
struct FriendActivityView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(FriendsStore.self) private var friendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var activity: [FriendActivity] = []
    @State private var loading = true
    @State private var selected: Restaurant?

    /// userID → display name, from the local follow list (cached snapshot).
    private var nameByID: [String: String] {
        Dictionary(friendsStore.friends.map { ($0.userID, $0.displayName) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// Restaurant lookup by id (defensive uniquing — seed can carry dupes).
    private var restaurantByID: [UUID: Restaurant] {
        Dictionary(store.restaurants.map { ($0.id, $0) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// Activity rows whose restaurant still exists in the catalog.
    private var rows: [FriendActivity] {
        activity.filter { restaurantByID[$0.restaurantID] != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading activity…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friendsStore.friends.isEmpty {
                    ContentUnavailableView {
                        Label("No friends yet", systemImage: "person.2")
                    } description: {
                        Text("Follow people to see what they're ranking. Open a friend's shared tier list and tap Follow.")
                    }
                } else if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No recent activity", systemImage: "clock")
                    } description: {
                        Text("The people you follow haven't ranked anything recently. Check back after they do.")
                    }
                } else {
                    List(rows) { item in
                        Button { selected = restaurantByID[item.restaurantID] } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Friend Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { r in
                NavigationStack { RestaurantDetailView(restaurant: r) }
                    .presentationDetents([.medium, .large])
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func row(_ item: FriendActivity) -> some View {
        let name = (nameByID[item.authorUserID] ?? "A foodie").trimmingCharacters(in: .whitespaces)
        let restaurant = restaurantByID[item.restaurantID]
        HStack(spacing: 12) {
            TierBadge(tier: item.tier, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                (Text(name.isEmpty ? "A foodie" : name).fontWeight(.semibold)
                 + Text(" ranked ").foregroundColor(.secondary)
                 + Text(restaurant?.name ?? "a spot").fontWeight(.semibold))
                    .font(.subheadline)
                    .lineLimit(2)
                Text(relative(item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func load() async {
        loading = true
        activity = await cloudKit.fetchFriendActivity(friendIDs: friendsStore.friendIDs)
        loading = false
    }
}
