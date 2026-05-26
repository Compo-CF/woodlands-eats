import SwiftUI

struct FilterBar: View {
    @Binding var filter: RestaurantFilter

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
