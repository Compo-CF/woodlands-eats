import SwiftUI

/// v2.7: skeleton placeholders shown while content loads, instead of a bare
/// spinner — reads more "designed" and gives a sense of the layout that's
/// about to appear. Plain gray shapes with a gentle opacity pulse (no shimmer
/// mask tricks — keeps it robust across iOS versions).

/// A soft opacity pulse applied to a whole skeleton group.
private struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private extension View {
    func pulsing() -> some View { modifier(Pulse()) }
}

/// One restaurant list-row placeholder (badge + two text bars + trailing meta).
struct RestaurantRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 170, height: 13)
                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).frame(width: 44, height: 12)
        }
        .foregroundStyle(Color(.systemGray4))
        .padding(.vertical, 6)
    }
}

/// A list of row skeletons — used for the Near Me loading state.
struct RestaurantListSkeleton: View {
    var rows = 8
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                RestaurantRowSkeleton().padding(.horizontal)
                Divider().opacity(0.3)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pulsing()
    }
}

/// The community board placeholder: five tier rows, each a tier badge + a
/// horizontal strip of restaurant cards.
struct CommunityBoardSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10).frame(width: 44, height: 44)
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12).frame(width: 110, height: 72)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(.systemGray4))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pulsing()
    }
}
