import SwiftUI
import MapKit

struct RestaurantDetailView: View {
    @Environment(TierListStore.self) private var tierStore
    let restaurant: Restaurant

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                rateSection
                if !restaurant.signatureDishes.isEmpty { dishesSection }
                aboutSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
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
                onSelect: { tierStore.setTier($0, for: restaurant.id) },
                onClear: { tierStore.removeTier(for: restaurant.id) }
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: restaurant.coordinate))
        item.name = restaurant.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
