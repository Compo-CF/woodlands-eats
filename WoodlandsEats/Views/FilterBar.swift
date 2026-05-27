import SwiftUI

struct FilterBar: View {
    @Binding var filter: RestaurantFilter
    @Environment(RestaurantStore.self) private var store
    @State private var showFilters = false

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
                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
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
