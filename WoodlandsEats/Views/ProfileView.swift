import SwiftUI

/// Profile + Foodie Pro request, and (for admins) in-app approval.
/// Identity is the implicit iCloud account; the display name is self-entered.
/// Approval is an admin-owned `ProApproval` record (a user can't edit another
/// user's FoodieProfile in the public DB), so approving is admin-gated.
struct ProfileView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @State private var displayName = ""
    @State private var status = ""        // "" | "requested" | "approved"
    @State private var userID = ""
    @State private var loading = true
    @State private var saving = false
    @State private var isAdmin = false
    @State private var pending: [ProRequest] = []
    @State private var approvedPros: [ProRequest] = []

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

                if isAdmin {
                    Section(header: Text("Pending Pro requests")) {
                        if pending.isEmpty {
                            Text("No pending requests").foregroundStyle(.secondary)
                        } else {
                            ForEach(pending) { req in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(req.displayName.isEmpty ? "(no name)" : req.displayName)
                                        Text(req.userID)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Approve") {
                                        Task { _ = await cloudKit.approvePro(userID: req.userID); await reloadAdmin() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }
                            }
                        }
                    }
                    if !approvedPros.isEmpty {
                        Section(header: Text("Foodie Pros")) {
                            ForEach(approvedPros) { req in
                                HStack {
                                    Label(req.displayName.isEmpty ? "(no name)" : req.displayName,
                                          systemImage: "star.fill")
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Button("Revoke") {
                                        Task { _ = await cloudKit.revokePro(userID: req.userID); await reloadAdmin() }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }

                if !userID.isEmpty {
                    Section(
                        header: Text("Your iCloud ID"),
                        footer: Text("Used to attribute your rankings.")
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
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        isAdmin = await cloudKit.isAdmin()
        if isAdmin { await reloadAdmin() }
        loading = false
    }

    private func reloadAdmin() async {
        let requests = await cloudKit.fetchProRequests()
        pending = requests.pending
        approvedPros = requests.approved
    }

    private func save(requestingPro: Bool) async {
        saving = true
        _ = await cloudKit.saveProfile(displayName: displayName, requestingPro: requestingPro)
        let profile = await cloudKit.fetchMyProfile()
        displayName = profile.displayName
        status = await cloudKit.amIApproved() ? "approved" : profile.status
        saving = false
    }
}
