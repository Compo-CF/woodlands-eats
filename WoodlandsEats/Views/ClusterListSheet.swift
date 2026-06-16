import SwiftUI

/// Sheet shown when the user taps a cluster on the map that can't be
/// separated by more zooming (multiple restaurants in the same building
/// or strip mall, where the annotation views collide at every zoom
/// level). Lists the restaurants inside the cluster so the user can pick
/// one explicitly — Apple Maps does the same thing.
///
/// Tap a row -> calls `onSelect` with the chosen restaurant, then this
/// sheet dismisses and the parent opens the regular restaurant detail.
struct ClusterListSheet: View {
    let restaurants: [Restaurant]
    let tierColor: (UUID) -> Color
    let onSelect: (Restaurant) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(restaurants.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { r in
                Button {
                    onSelect(r)
                } label: {
                    HStack(spacing: 12) {
                        // Small tier-colored swatch on the leading edge —
                        // mirrors the pin color the user just tapped.
                        Circle()
                            .fill(tierColor(r.id))
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(r.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !r.cuisines.isEmpty {
                                Text(r.cuisineSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("\(restaurants.count) restaurants here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
