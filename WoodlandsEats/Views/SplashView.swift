import SwiftUI

/// v2.8: a brief animated splash shown on cold launch. The five tier badges
/// spring in one after another and the wordmark fades up, then the app cross-
/// fades in (see WoodlandsEatsApp). Pure presentation — no data work here.
///
/// The background matches the static UILaunchScreen color (LaunchBackground),
/// so the hand-off from the system launch image to this view is seamless.
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.102, green: 0.094, blue: 0.141),
                         Color(red: 0.047, green: 0.043, blue: 0.067)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Soft brand-purple glow behind the badges.
            RadialGradient(
                colors: [Color(red: 0.42, green: 0.36, blue: 0.96).opacity(0.30), .clear],
                center: .center, startRadius: 8, endRadius: 420)
                .ignoresSafeArea()
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.8), value: appear)

            VStack(spacing: 28) {
                HStack(spacing: 12) {
                    ForEach(Array(Tier.allCases.enumerated()), id: \.offset) { index, tier in
                        Text(tier.label)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(tier.color,
                                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .scaleEffect(appear ? 1 : 0.4)
                            .opacity(appear ? 1 : 0)
                            .animation(.spring(response: 0.55, dampingFraction: 0.62)
                                .delay(Double(index) * 0.08), value: appear)
                    }
                }

                Text("S-Tier Eats")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(.easeOut(duration: 0.5).delay(0.46), value: appear)
            }
        }
        .onAppear { appear = true }
    }
}
