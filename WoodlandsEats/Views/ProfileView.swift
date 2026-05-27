import SwiftUI

/// Profile + Foodie Pro request. Identity is the implicit iCloud account; the
/// display name is self-entered (no Sign in with Apple yet). Requesting Pro sets
/// the profile status to "requested"; an admin approves it (manually in the
/// CloudKit console for now). Approved Pros power the Pros leaderboard.
struct ProfileView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @State private var displayName = ""
    @State private var status = ""        // "" | "requested" | "approved"
    @State private var userID = ""
    @State private var loading = true
    @State private var saving = false

    private var nameEmpty: Bool {
        displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Display name"),
                    footer: Text("Shown with your reviews and on the Foodie Pro leaderboard.")
                ) {
                    TextField("Your name", text: $displayName)
                        .autocorrectionDisabled()
                    Button("Save name") {
                        Task { await save(requestingPro: false) }
                    }
                    .disabled(saving || nameEmpty)
                }

                Section(
                    header: Text("Foodie Pro"),
                    footer: Text("Foodie Pros' rankings power the \u{201C}Pros\u{201D} leaderboard on the Community tab. Set a display name first, then request.")
                ) {
                    switch status {
                    case "approved":
                        Label("You're a Foodie Pro", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                    case "requested":
                        Label("Request pending approval", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    default:
                        Button {
                            Task { await save(requestingPro: true) }
                        } label: {
                            Label("Request Foodie Pro", systemImage: "star")
                        }
                        .disabled(saving || nameEmpty)
                    }
                }

                if !userID.isEmpty {
                    Section(
                        header: Text("Your iCloud ID"),
                        footer: Text("Used to attribute your rankings. (For admin setup.)")
                    ) {
                        Text(userID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Profile")
            .overlay {
                if loading { ProgressView() }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        userID = await cloudKit.currentUserID() ?? ""
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        status = profile.status
        loading = false
    }

    private func save(requestingPro: Bool) async {
        saving = true
        _ = await cloudKit.saveProfile(displayName: displayName, requestingPro: requestingPro)
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        status = profile.status
        saving = false
    }
}
