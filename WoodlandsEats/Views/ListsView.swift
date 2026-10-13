import SwiftUI

/// v3.0: the user's shareable restaurant Lists ("Top 10 Tacos", etc.).
/// Reached from the My Tiers tab. Create / rename / delete here; tap a list to
/// open its detail (reorder, add/remove, share).
struct ListsView: View {
    @Environment(RestaurantStore.self) private var store
    @State private var lists: [RestaurantList] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var newTitle = ""

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lists.isEmpty {
                ContentUnavailableView {
                    Label("No lists yet", systemImage: "list.star")
                } description: {
                    Text("Make a list like \u{201C}Top 10 Tacos\u{201D} and share it with friends.")
                } actions: {
                    Button("Create a list") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(lists) { list in
                        NavigationLink(value: list) { row(list) }
                    }
                    .onDelete { offsets in Task { await delete(offsets) } }
                }
            }
        }
        .navigationTitle("My Lists")
        .navigationDestination(for: RestaurantList.self) { list in
            ListDetailView(list: list) { Task { await load() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New list", isPresented: $showCreate) {
            TextField("Title (e.g. Top 10 Tacos)", text: $newTitle)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .task { await load() }
    }

    private func row(_ list: RestaurantList) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(list.emoji.isEmpty ? "📋" : list.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title).font(.headline)
                Text("\(list.restaurantIDs.count) \(list.restaurantIDs.count == 1 ? "spot" : "spots")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if list.isPublic {
                Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        lists = await FirebaseService.shared.fetchMyLists()
        loading = false
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        newTitle = ""
        guard !title.isEmpty else { return }
        _ = await FirebaseService.shared.createList(title: title, emoji: "", isPublic: true)
        await load()
    }

    private func delete(_ offsets: IndexSet) async {
        for i in offsets { await FirebaseService.shared.deleteList(lists[i].id) }
        await load()
    }
}
