import SwiftUI

/// One-time picker shown the first time the user taps "Order" on a restaurant
/// that supports delivery / takeout. The choice persists to UserDefaults via
/// `DeliveryPreference`, so future Order taps deeplink straight into the
/// chosen app's search results without re-asking.
///
/// User can reset the preference later from the Profile tab.
struct DeliveryPickerSheet: View {
    let onSelect: (DeliveryApp) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Which delivery app?")
                    .font(.title3.weight(.semibold))
                Text("We'll remember your choice. You can change it later in Profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 24)

            VStack(spacing: 10) {
                ForEach(DeliveryApp.allCases) { app in
                    Button {
                        onSelect(app)
                    } label: {
                        HStack {
                            Image(systemName: app.systemImage)
                            Text(app.displayName)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(app == .doordash ? Color.red : Color.black,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal)

            Button("Cancel") { dismiss() }
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }
}
