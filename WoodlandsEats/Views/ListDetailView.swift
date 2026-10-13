import SwiftUI

/// v3.0: one restaurant List — reorder, add, remove, rename, toggle public.
/// `readOnly` renders the shared/deep-link view (no editing). Writes persist to
/// Firestore via FirebaseService and call `onChange` so the parent list refreshes.
struct ListDetailView: View {
    @Environment(RestaurantStore.self) private var store
    @State private var list: RestaurantList
    private let readOnly: Bool
    private let onChange: () -> Void

    @State private var showAdd = false
    @State private var showRename = false
    @State private var editTitle = ""
    @State private var editEmoji = ""
    @Environment(\.displayScale) private var displayScale
    @State private var shareImage: UIImage?

    init(list: RestaurantList, readOnly: Bool = false, onChange: @escaping () -> Void = {}) {
        _list = State(initialValue: list)
        self.readOnly = readOnly
        self.onChange = onChange
    }

    private var byID: [UUID: Restaurant] {
        Dictionary(store.restaurants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        List {
            Section {
                if list.restaurantIDs.isEmpty {
                    Text(readOnly ? "This list is empty." : "Add restaurants with the + button.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(list.restaurantIDs, id: \.self) { id in
                        if let r = byID[id] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.body.weight(.semibold))
                                Text(r.cuisineSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove(perform: readOnly ? nil : move)
                    .onDelete(perform: readOnly ? nil : remove)
                }
            } footer: {
                Text("\(list.restaurantIDs.count) \(list.restaurantIDs.count == 1 ? "spot" : "spots")")
            }

            if !readOnly {
                Section {
                    Toggle("Public (shareable)", isOn: Binding(
                        get: { list.isPublic },
                        set: { list.isPublic = $0; persist() }
                    ))
                } footer: {
                    Text("Public lists can be opened by anyone with the link.")
                }
            }
        }
        .navigationTitle(list.emoji.isEmpty ? list.title : "\(list.emoji) \(list.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let img = shareImage, !list.restaurantIDs.isEmpty {
                    Menu {
                        ShareLink(
                            item: ShareableListImage(uiImage: img),
                            preview: SharePreview(list.title, image: Image(uiImage: img))
                        ) { Label("Share as image", systemImage: "photo") }
                        if list.isPublic,
                           let url = URL(string: "https://compo-cf.github.io/woodlands-eats/list/\(list.id)") {
                            ShareLink(item: url, subject: Text(list.title),
                                      message: Text("Check out my list on S-Tier Eats:")) {
                                Label("Share link", systemImage: "link")
                            }
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            if !readOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { startRename() } label: { Label("Rename", systemImage: "pencil") }
                        Button { showAdd = true } label: { Label("Add restaurant", systemImage: "plus") }
                        EditButton()
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .onAppear { rebuildShareImage() }
        .onChange(of: list.restaurantIDs) { _, _ in rebuildShareImage() }
        .onChange(of: list.title) { _, _ in rebuildShareImage() }
        .onChange(of: list.emoji) { _, _ in rebuildShareImage() }
        .sheet(isPresented: $showAdd) {
            AddToListSheet(existing: Set(list.restaurantIDs)) { picked in
                list.restaurantIDs.append(picked)
                persist()
            }
        }
        .alert("Rename list", isPresented: $showRename) {
            TextField("Title", text: $editTitle)
            TextField("Emoji (optional)", text: $editEmoji)
            Button("Save") { applyRename() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func move(_ offsets: IndexSet, _ dest: Int) {
        list.restaurantIDs.move(fromOffsets: offsets, toOffset: dest)
        persist()
    }

    private func remove(_ offsets: IndexSet) {
        list.restaurantIDs.remove(atOffsets: offsets)
        persist()
    }

    private func startRename() {
        editTitle = list.title
        editEmoji = list.emoji
        showRename = true
    }

    private func applyRename() {
        let t = editTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        list.title = t
        list.emoji = String(editEmoji.prefix(2)).trimmingCharacters(in: .whitespaces)
        persist()
    }

    private func persist() {
        let snapshot = list
        Task {
            await FirebaseService.shared.updateList(
                snapshot.id, title: snapshot.title, emoji: snapshot.emoji,
                restaurantIDs: snapshot.restaurantIDs, isPublic: snapshot.isPublic
            )
            onChange()
        }
    }

    /// Render the off-screen ListShareCard to a UIImage for ShareLink.
    @MainActor private func rebuildShareImage() {
        let names = list.restaurantIDs.compactMap { byID[$0]?.name }
        guard !names.isEmpty else { shareImage = nil; return }
        let renderer = ImageRenderer(content: ListShareCard(title: list.title, emoji: list.emoji, names: names))
        renderer.scale = displayScale
        shareImage = renderer.uiImage
    }
}

/// Searchable picker for adding a restaurant to a list (excludes ones already in it).
private struct AddToListSheet: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: Set<UUID>
    let onPick: (UUID) -> Void
    @State private var query = ""

    private var results: [Restaurant] {
        let base = store.restaurants.filter { !existing.contains($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(base.prefix(50)) }
        return base.filter {
            $0.name.lowercased().contains(q) || $0.cuisineSummary.lowercased().contains(q)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List(results) { r in
                Button {
                    onPick(r.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(r.cuisineSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search restaurants")
            .navigationTitle("Add restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
