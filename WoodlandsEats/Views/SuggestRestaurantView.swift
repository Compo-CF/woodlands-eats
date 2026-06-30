import SwiftUI

/// User-facing form to submit a missing restaurant. The submission creates a
/// user-owned RestaurantSuggestion record; the admin approves it from the
/// Profile tab, which creates a LiveRestaurant the app fetches into its list.
struct SuggestRestaurantView: View {
    @Environment(CloudKitService.self) private var cloudKit
    /// v1.6 (Android migration A2): cross-platform dual-write target.
    @Environment(FirebaseService.self) private var firebase
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var area: Area = .woodlands
    @State private var cuisine: Cuisine = .american
    @State private var description = ""
    @State private var submitting = false
    @State private var submittedOK = false
    @State private var error: String?

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Restaurant"),
                    footer: Text("An admin reviews suggestions before they appear. Use the full street address — that's how we pin it on the map.")
                ) {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Street address (incl. city, TX, zip)", text: $address)
                        .autocorrectionDisabled()
                    Picker("Area", selection: $area) {
                        ForEach(Area.allCases) { a in Text(a.displayName).tag(a) }
                    }
                    Picker("Cuisine", selection: $cuisine) {
                        ForEach(Cuisine.allCases) { c in Text(c.displayName).tag(c) }
                    }
                }
                Section(header: Text("Anything else? (optional)")) {
                    TextField("What it's known for, when it opened, etc.",
                              text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.subheadline) }
                }
                if submittedOK {
                    Section {
                        Label("Submitted — thanks!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Suggest a spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(!ready || submitting)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        error = nil
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanAddress = address.trimmingCharacters(in: .whitespaces)
        let cleanDescription = description.trimmingCharacters(in: .whitespaces)
        let ok = await cloudKit.submitSuggestion(
            name: cleanName,
            address: cleanAddress,
            area: area.rawValue,
            cuisines: [cuisine.rawValue],
            description: cleanDescription
        )
        // v1.6 dual-write: Firestore stores its own auto-ID for the
        // suggestion. The two stores' suggestion IDs diverge — the
        // migration step reconciles them later.
        Task {
            _ = await firebase.saveSuggestion(
                name: cleanName,
                address: cleanAddress,
                area: area.rawValue,
                cuisines: [cuisine.rawValue],
                description: cleanDescription
            )
        }
        submitting = false
        if ok {
            submittedOK = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } else {
            error = "Couldn't submit — check your connection and iCloud sign-in."
        }
    }
}
