import SwiftUI

/// First-launch terms-of-use gate. App Review Guideline 1.2 requires apps
/// with user-generated content to present an EULA the user must agree to
/// before using the app, with explicit "no tolerance for objectionable
/// content or abusive users" language. The "I Agree" tap flips the
/// `@AppStorage` flag in `WoodlandsEatsApp`, which swaps this view out for
/// `ContentView`.
///
/// The full Apple Standard EULA is linked at the bottom; the visible text
/// above is the consumer-friendly summary that calls out the UGC rules
/// Apple explicitly looks for.
struct EULAView: View {
    @Binding var hasAccepted: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to S-Tier Eats")
                        .font(.largeTitle.bold())
                        .padding(.top, 24)

                    Text("Before you start ranking restaurants, please review and accept the terms below.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Community standards")
                        .font(.title3.weight(.semibold))

                    VStack(alignment: .leading, spacing: 12) {
                        ruleRow(
                            icon: "xmark.shield.fill",
                            tint: .red,
                            text: "**Zero tolerance for objectionable content** — including hateful, harassing, sexually explicit, violent, or illegal material."
                        )
                        ruleRow(
                            icon: "xmark.shield.fill",
                            tint: .red,
                            text: "**Zero tolerance for abusive behavior** toward other users."
                        )
                        ruleRow(
                            icon: "flag.fill",
                            tint: .orange,
                            text: "Long-press any photo to **report it** or **block its uploader**. Reports go to the app's administrator within 24 hours."
                        )
                        ruleRow(
                            icon: "trash.fill",
                            tint: .red,
                            text: "Content that violates these standards is **removed immediately** upon review. Users who post violating content may be **removed from the service without notice**."
                        )
                    }

                    Divider()

                    Text("What you upload")
                        .font(.title3.weight(.semibold))

                    Text("Dish photos and restaurant suggestions you submit become part of the community catalog and may be shown to other users. Your opaque iCloud user identifier is attached so others can report or block you if needed. Your Apple ID, email, and real name are never shared.")
                        .font(.callout)

                    Divider()

                    Text("Full terms")
                        .font(.title3.weight(.semibold))

                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Apple Standard EULA (full text)")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        .font(.callout)
                    }

                    Link(destination: URL(string: "https://compo-cf.github.io/woodlands-eats/privacy.html")!) {
                        HStack {
                            Image(systemName: "lock.shield")
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        .font(.callout)
                    }

                    Divider()

                    Text("Contact")
                        .font(.title3.weight(.semibold))

                    Link(destination: URL(string: "mailto:acompofelice@outlook.com")!) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("acompofelice@outlook.com")
                            Spacer()
                        }
                        .font(.callout)
                    }
                    Text("Email for content takedown, abuse reports, or any questions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Persistent footer with the agree action. Lives outside the
            // ScrollView so it's always visible — Apple's reviewer needs to
            // see the agreement gate clearly without scrolling.
            VStack(spacing: 8) {
                Button {
                    hasAccepted = true
                } label: {
                    Text("I Agree")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Text("By tapping I Agree, you accept the terms above.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.ultraThinMaterial)
        }
    }

    private func ruleRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .padding(.top, 2)
                .frame(width: 22)
            Text(.init(text))   // .init enables markdown bold via **...**
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
