import SwiftUI

/// v1.3: three-screen first-launch flow. Replaces the bare tier-guide
/// sheet that auto-showed pre-v1.3. Surfaces:
///   1. What S-Tier Eats does (welcome + the "no star averages" pitch)
///   2. How the S/A/B/C/F tier system works (reuses TierGuide content)
///   3. Why we want location + an in-app explanation before the iOS prompt
///
/// Driven by @AppStorage("WoodlandsEats.hasCompletedOnboarding"). Existing
/// pre-v1.3 users get auto-migrated in ContentView (if they already saw
/// the old tier guide, we mark them onboarded so they don't get this).
///
/// Re-runnable from Profile -> "Show app tour" — useful if a friend hands
/// the user the app or for showing the tour without uninstalling.
struct OnboardingView: View {
    /// Bound from the caller (full-screen cover binding or @AppStorage). When
    /// flipped to true the view's containing fullScreenCover dismisses.
    @Binding var hasCompletedOnboarding: Bool
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var page: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                tiersPage.tag(1)
                locationPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Skip is visible on every page so a returning user can bail
            // immediately. Hidden on the final page since the explicit
            // "Enable location" / "Not now" buttons make Skip redundant.
            if page < 2 {
                Button("Skip") { finish() }
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "fork.knife.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(Tier.s.color)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 12) {
                Text("Welcome to S-Tier Eats")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Rank every restaurant in The Woodlands area on a tier list. No more 4.2-star averages — just S, A, B, C, or F.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
            primaryButton("Continue") { page = 1 }
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
    }

    private var tiersPage: some View {
        VStack(spacing: 18) {
            Text("How tiers work")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 32)

            Text("Five letters. One honest signal — to your future self and the rest of the community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(Tier.allCases) { tier in
                    tierRow(tier)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
            primaryButton("Continue") { page = 2 }
                .padding(.bottom, 48)
        }
    }

    private func tierRow(_ tier: Tier) -> some View {
        HStack(spacing: 14) {
            Text(tier.label)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tier.color, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.blurb)
                    .font(.headline)
                Text(shortDetail(for: tier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    /// Trimmed versions of TierGuideView.detail so the onboarding card fits
    /// on phone screens without scrolling. Full text still lives in Profile
    /// -> "Tier guide" for users who want the deeper explanation.
    private func shortDetail(for tier: Tier) -> String {
        switch tier {
        case .s: return "Drive past three other options to get here."
        case .a: return "You'd suggest this to a visiting friend."
        case .b: return "Solid. Happy to come back."
        case .c: return "Functional. Go if someone else picks."
        case .f: return "Skip. The community needs honest Fs."
        }
    }

    private var locationPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 12) {
                Text("Find spots near you")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Allow location so we can sort restaurants by distance and show your position on the map. The app works fine without it — you'll just lose the “Nearby” sort and the blue dot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                primaryButton("Enable location") {
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestPermission()
                    }
                    finish()
                }
                Button("Not now") { finish() }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Tier.s.color, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
    }

    private func finish() {
        hasCompletedOnboarding = true
        // Also mark the old tier-guide flag so it never auto-shows again
        // for fresh installs that go through onboarding first.
        UserDefaults.standard.set(true, forKey: "WoodlandsEats.hasSeenTierGuide")
        dismiss()
    }
}

/// Wrapper for re-running the onboarding flow from Profile -> "Show app tour".
/// Uses a local @State for the completion binding so flipping it on finish
/// doesn't affect the persistent hasCompletedOnboarding flag — the user is
/// already onboarded; this is just for re-viewing the tour.
struct AppTourWrapper: View {
    @Binding var isPresented: Bool
    @State private var localCompleted = false

    var body: some View {
        OnboardingView(hasCompletedOnboarding: $localCompleted)
            .onChange(of: localCompleted) { _, done in
                if done { isPresented = false }
            }
    }
}
