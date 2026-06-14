import SwiftUI

struct FilterBar: View {
    @Binding var filter: RestaurantFilter
    @Environment(RestaurantStore.self) private var store
    @State private var showFilters = false
    /// Build 28: explicit focus state so we can guarantee the keyboard is
    /// released on every dismissal path — Done button on the keyboard
    /// toolbar, return key, X-to-clear tap, and an empty submit. Prior to
    /// this the user could end up wedged with the keyboard up and the tab
    /// bar hidden, having to kill the app to recover.
    @FocusState private var searchFocused: Bool

    private var filterCount: Int {
        filter.selectedCuisines.count + filter.selectedPrices.count + (filter.includeFastFood ? 1 : 0)
    }

    private var availableCuisines: [Cuisine] {
        let present = Set(store.restaurants.flatMap { $0.cuisines })
        return Cuisine.allCases.filter { present.contains($0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search restaurants or cuisine", text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6), in: .capsule)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { showFilters = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text(filterCount > 0 ? "Filters · \(filterCount)" : "Filters")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(filterCount > 0 ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                        .foregroundStyle(filterCount > 0 ? .white : .primary)
                    }
                    .buttonStyle(.plain)

                    // Build 28: "Ranked only" chip — filters the map and the
                    // Browse list down to restaurants the user has placed in a
                    // tier. Useful for treating the map as a personal taste
                    // snapshot.
                    FilterChip(title: "Ranked only",
                               isOn: filter.rankedOnly) {
                        filter.rankedOnly.toggle()
                    }

                    ForEach(Area.allCases) { area in
                        FilterChip(title: area.displayName,
                                   isOn: filter.selectedAreas.contains(area)) {
                            if filter.selectedAreas.contains(area) {
                                filter.selectedAreas.remove(area)
                            } else {
                                filter.selectedAreas.insert(area)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .toolbar {
            // Anchors a Done button to the iOS input accessory bar above the
            // keyboard so the user always has an explicit dismiss path. Only
            // visible while a TextField in this view has focus.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .sheet(isPresented: $showFilters) {
            FiltersView(filter: $filter, availableCuisines: availableCuisines)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
