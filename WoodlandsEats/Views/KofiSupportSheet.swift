import SwiftUI

/// v1.5: support-the-developer sheet shown after the Connoisseur
/// rank-up celebration dismisses. One-shot per major version (gated
/// by @AppStorage in ContentView; key suffix bumps each major).
///
/// Distinct from the onboarding tour's support screen — that runs
/// once at first launch when the user has zero usage. This one fires
/// at Connoisseur (30 placements), well after the user has
/// demonstrated sustained engagement, so the ask feels earned rather
/// than transactional.
///
/// Two outs: 'Buy me a coffee' opens Ko-fi in Safari + dismisses,
/// 'Maybe later' dismisses silently. No third option to ensure the
/// prompt never blocks the user beyond a single tap.
struct KofiSupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cup.and.saucer.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .foregroundStyle(Tier.s.color)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 12) {
                Text("You've been at this a while.")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("S-Tier Eats is made by one person and stays free for everyone. If it's earned a place in your routine, a small tip on Ko-fi keeps the lights on and funds new features.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    if let url = URL(string: "https://ko-fi.com/subtlefoodie") {
                        openURL(url)
                    }
                    dismiss()
                } label: {
                    Text("Buy me a coffee")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Tier.s.color, in: Capsule())
                        .foregroundStyle(.white)
                }
                Button("Maybe later") { dismiss() }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
