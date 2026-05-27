import SwiftUI

/// Filter sheet: the fast-food toggle, price, and multi-select cuisine.
/// (Search + area chips stay inline in FilterBar.)
struct FiltersView: View {
    @Binding var filter: RestaurantFilter
    let availableCuisines: [Cuisine]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include fast food", isOn: $filter.includeFastFood)
                } footer: {
                    Text("Commodity fast-food chains (McDonald's, drive-thrus, etc.) are hidden by default so your tier list stays focused on places worth ranking. Notable quick-service spots like Whataburger or Torchy's always show.")
                }

                Section("Price") {
                    HStack(spacing: 8) {
                        ForEach(PriceTier.allCases) { price in
                            priceChip(price)
                        }
                    }
                }

                Section("Cuisine") {
                    if filter.selectedCuisines.isEmpty {
                        Text("All cuisines")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(availableCuisines) { cuisine in
                        Button {
                            toggleCuisine(cuisine)
                        } label: {
                            HStack {
                                Text(cuisine.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filter.selectedCuisines.contains(cuisine) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { filter.clear() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleCuisine(_ cuisine: Cuisine) {
        if filter.selectedCuisines.contains(cuisine) {
            filter.selectedCuisines.remove(cuisine)
        } else {
            filter.selectedCuisines.insert(cuisine)
        }
    }

    private func priceChip(_ price: PriceTier) -> some View {
        let on = filter.selectedPrices.contains(price)
        return Button {
            if on { filter.selectedPrices.remove(price) } else { filter.selectedPrices.insert(price) }
        } label: {
            Text(price.displayName)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
