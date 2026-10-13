import SwiftUI
import UniformTypeIdentifiers

/// v3.0: a square-friendly share image for a Restaurant List, rendered off-screen
/// via ImageRenderer (same approach as ShareableTierCard). A numbered list reads
/// naturally as a "Top N" ranking. Fixed 1080×1350 (4:5), forced light mode so it
/// looks the same for whoever it's shared to.
struct ListShareCard: View {
    let title: String
    let emoji: String
    let names: [String]
    private let cap = 15

    var body: some View {
        let shown = Array(names.prefix(cap))
        let extra = names.count - shown.count
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("S-TIER EATS")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.secondary)
                Text(emoji.isEmpty ? title : "\(emoji) \(title)")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 48)
            }
            .padding(.top, 60)
            .padding(.bottom, 28)

            Divider().padding(.horizontal, 48)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, name in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(i + 1)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.nightOut)
                            .frame(width: 52, alignment: .trailing)
                        Text(name)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                if extra > 0 {
                    Text("+\(extra) more")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 68)
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text("Make your own list")
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

/// File-based Transferable so the share sheet offers Save to Photos + all the
/// file-based share extensions (same reasoning as ShareableTierImage).
struct ShareableListImage: Transferable {
    let uiImage: UIImage
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { wrapper in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("STierList.png")
            if let data = wrapper.uiImage.pngData() { try? data.write(to: url, options: .atomic) }
            return SentTransferredFile(url)
        }
        .suggestedFileName("STierList.png")
    }
}
