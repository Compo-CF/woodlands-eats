import SwiftUI

/// v3.0 Phase 2b (Social): the "Taste Match Leaderboard" — ranks everyone you
/// follow by how closely their tier list agrees with yours. Extends the 1:1
/// comparison in FriendCompareView to a sorted board: fetch each friend's
/// placements once (concurrently), score agreement over your shared spots, and
/// list them best-match-first. Tapping a friend opens the full FriendCompareView.
///
/// Pull-based like FriendActivityView — opened from the Community Friends board.
/// Friends with no overlapping rankings yet sink to the bottom as "no overlap".
struct TasteMatchLeaderboardView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(FriendsStore.self) private var friendsStore
    @Environment(TierListStore.self) private var tierStore
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Entry] = []
    @State private var loading = true
    @State private var selected: Entry?

    /// One friend's scored match plus the raw placements we fetched (reused by
    /// FriendCompareView so it doesn't re-fetch).
    struct Entry: Identifiable {
        let userID: String
        let displayName: String
        let placements: [(restaurantID: UUID, tier: Tier)]
        let overlap: Int        // spots you've both ranked
        let agree: Int          // of those, same tier
        var id: String { userID }
        var matchPct: Int {
            overlap == 0 ? 0 : Int((Double(agree) / Double(overlap) * 100).rounded())
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Scoring your matches…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friendsStore.friends.isEmpty {
                    ContentUnavailableView {
                        Label("No friends yet", systemImage: "person.2")
                    } description: {
                        Text("Follow people to see who shares your taste. Open a friend's shared tier list and tap Follow.")
                    } actions: {
                        InviteFriendButton()
                    }
                } else {
                    List {
                        if myRankedCount < 3 {
                            Section {
                                Text("Rank a few more spots to sharpen your matches — the more you've both ranked, the more meaningful the score.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                                Button { selected = entry } label: { row(rank: idx + 1, entry) }
                                    .buttonStyle(.plain)
                                    .disabled(entry.overlap == 0)
                            }
                        }
                        Section {
                            InviteFriendButton()
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Taste Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { entry in
                FriendCompareView(friendName: entry.displayName,
                                  friendPlacements: entry.placements)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var myRankedCount: Int { tierStore.placements.count }

    @ViewBuilder
    private func row(rank: Int, _ entry: Entry) -> some View {
        HStack(spacing: DS.Space.md) {
            rankBadge(rank, matched: entry.overlap > 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName.isEmpty ? "A foodie" : entry.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if entry.overlap > 0 {
                    Text("\(entry.overlap) shared · agree on \(entry.agree)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No overlap yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if entry.overlap > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(entry.matchPct)%")
                        .font(.grotesk(26, .bold))
                        .foregroundStyle(Color.nightOut)
                    Text("match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Medal for the top three matches, a plain number otherwise. Greyed out
    /// when there's no overlap to rank on.
    @ViewBuilder
    private func rankBadge(_ rank: Int, matched: Bool) -> some View {
        let medal: Color? = (rank == 1 && matched) ? .yellow
            : (rank == 2 && matched) ? .gray
            : (rank == 3 && matched) ? .brown : nil
        ZStack {
            Circle()
                .fill(medal?.opacity(0.22) ?? Color(.secondarySystemBackground))
                .frame(width: 40, height: 40)
            if let medal {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(medal)
            } else {
                Text("\(rank)")
                    .font(.grotesk(16, .bold))
                    .foregroundStyle(matched ? .primary : .tertiary)
            }
        }
    }

    private func load() async {
        loading = true
        let myMap = tierStore.placements  // [UUID: Tier]
        let friends = friendsStore.friends

        // Fetch every friend's placements concurrently, then score locally.
        let fetched: [(Friend, [(restaurantID: UUID, tier: Tier)])] = await withTaskGroup(
            of: (Friend, [(restaurantID: UUID, tier: Tier)]).self
        ) { group in
            for friend in friends {
                group.addTask {
                    let p = await cloudKit.fetchPlacements(forUserID: friend.userID)
                    return (friend, p)
                }
            }
            var out: [(Friend, [(restaurantID: UUID, tier: Tier)])] = []
            for await result in group { out.append(result) }
            return out
        }

        let scored = fetched.map { friend, placements -> Entry in
            var overlap = 0, agree = 0
            for (rid, theirs) in placements {
                guard let mine = myMap[rid] else { continue }
                overlap += 1
                if mine == theirs { agree += 1 }
            }
            return Entry(userID: friend.userID,
                         displayName: friend.displayName,
                         placements: placements,
                         overlap: overlap,
                         agree: agree)
        }

        // Best match first; ties broken by more shared spots, then name.
        // Friends with no overlap sink to the bottom.
        entries = scored.sorted {
            if ($0.overlap > 0) != ($1.overlap > 0) { return $0.overlap > 0 }
            if $0.matchPct != $1.matchPct { return $0.matchPct > $1.matchPct }
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        loading = false
    }
}
