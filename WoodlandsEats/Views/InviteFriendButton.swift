import SwiftUI

/// v2.2: "Invite a friend to compare taste" — the referral loop. Taste
/// Match is inherently two-player, so this shares the user's own tier link
/// (or the App Store listing as a fallback) with a hook that invites the
/// recipient to install, rank their spots, and see their Taste Match. Every
/// send is a potential App-Referrer install — the app's strongest growth
/// channel.
///
/// `prominent` renders a filled full-width button (empty states, footers);
/// otherwise a plain label suitable for a menu or list row.
struct InviteFriendButton: View {
    var prominent = true

    /// Written by ProfileView / MyTiersView once the CloudKit userRecordName
    /// is known — lets us deep-link the friend straight to the sender's list.
    @AppStorage("WoodlandsEats.cachedUserID") private var cachedUserID = ""

    private var inviteURL: URL {
        if !cachedUserID.isEmpty,
           let u = URL(string: "https://compo-cf.github.io/woodlands-eats/tier/\(cachedUserID)") {
            return u   // lands on the sender's shared tier list → Follow → compare
        }
        return URL(string: "https://apps.apple.com/app/id6773501518")!
    }

    private var message: Text {
        Text("See how your restaurant taste compares to mine on S-Tier Eats 👀 Rank your spots and check your Taste Match with me.")
    }

    var body: some View {
        if prominent {
            shareLink
                .buttonStyle(.borderedProminent)
                .tint(Color.nightOut)
        } else {
            shareLink
        }
    }

    private var shareLink: some View {
        ShareLink(
            item: inviteURL,
            subject: Text("Compare our taste on S-Tier Eats"),
            message: message
        ) {
            Label("Invite a friend to compare taste", systemImage: "person.badge.plus")
                .font(prominent ? .headline : .body)
                .frame(maxWidth: prominent ? .infinity : nil)
                .padding(.vertical, prominent ? 8 : 0)
        }
    }
}
