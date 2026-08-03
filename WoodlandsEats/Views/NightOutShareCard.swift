import SwiftUI
import UniformTypeIdentifiers

/// v2.2: Transferable PNG wrapper for the "Tonight's Pick" share card.
/// File-based (not data-based) so the iOS share sheet offers "Save to
/// Photos" in addition to Messages/Mail/AirDrop — same rationale as
/// ShareableTierImage.
struct NightOutShareImage: Transferable {
    let uiImage: UIImage

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { wrapper in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TonightsPick.png")
            if let data = wrapper.uiImage.pngData() {
                try? data.write(to: url, options: .atomic)
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName("TonightsPick.png")
    }
}

/// v2.2: a square-friendly "Tonight's Pick" card rendered off-screen via
/// ImageRenderer so a Night Out result can be shared to Messages,
/// Instagram, etc. Turning the decision into a shareable image is a
/// deliberate growth hook — shares land as App-Referrer installs.
///
/// Fixed 1080×1350 (4:5) and forced light mode so it looks the same for
/// whoever receives it, regardless of the sender's color scheme.
struct NightOutShareCard: View {
    let pick: NightOutPick
    let note: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 90)

            Text("S-TIER EATS")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(5)
                .foregroundStyle(.secondary)
            Text("TONIGHT'S PICK")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.nightOut)
                .padding(.top, 6)

            Text(pick.tier.label)
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 200, height: 200)
                .background(pick.tier.color, in: RoundedRectangle(cornerRadius: 44))
                .padding(.top, 40)

            Text(pick.restaurant.name)
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 60)
                .padding(.top, 40)

            Text(pick.restaurant.cuisineSummary)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            HStack(spacing: 14) {
                Label(pick.restaurant.priceTier.displayName, systemImage: "dollarsign.circle")
                Label(pick.restaurant.area.displayName, systemImage: "mappin.and.ellipse")
            }
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 18)

            if let note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.system(size: 28, weight: .regular, design: .rounded).italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 70)
                    .padding(.top, 26)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("Can't decide where to eat?")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("apps.apple.com/app/id6773501518")
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 60)
        }
        .frame(width: 1080, height: 1350)
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .light)
    }
}
