import SwiftUI
import UniformTypeIdentifiers

/// v3.0 "Food Wrapped": a shareable summary of the user's ranking stats,
/// rendered off-screen via ImageRenderer. 1080×1350 (4:5), forced light mode.
/// Reuses the values MyStatsView already computes.
struct StatsShareCard: View {
    let displayName: String
    let headline: String        // e.g. "My Food Stats" or "2026 in Food"
    let rankName: String
    let rankedCount: Int
    let visitedCount: Int
    let sTierCount: Int
    let topCuisine: String?
    let topArea: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("S-TIER EATS")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                if !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(displayName)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 24)

            // Rank pill
            Text(rankName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.nightOut, in: Capsule())
                .padding(.bottom, 28)

            // Stat tiles
            let tiles: [(String, String)] = [
                ("\(rankedCount)", "Ranked"),
                ("\(sTierCount)", "S-Tier picks"),
                ("\(visitedCount)", "Visited"),
                (topCuisine ?? "—", "Top cuisine"),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    VStack(spacing: 6) {
                        Text(t.0)
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(t.1)
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 48)

            if let topArea {
                Text("Most-explored area: \(topArea)")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text("Rank your local restaurants")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("apps.apple.com/app/id6773501518")
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 44)
        }
        .frame(width: 1080, height: 1350)
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .light)
    }
}

struct ShareableStatsImage: Transferable {
    let uiImage: UIImage
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { wrapper in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyFoodStats.png")
            if let data = wrapper.uiImage.pngData() { try? data.write(to: url, options: .atomic) }
            return SentTransferredFile(url)
        }
        .suggestedFileName("MyFoodStats.png")
    }
}
