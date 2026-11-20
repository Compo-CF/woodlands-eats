import SwiftUI

/// v3.0 design system — shared tokens for the "Social & Shareable" refresh.
/// Space Grotesk is the display face (bundled static instances, referenced by
/// PostScript name); the system font stays the body face.
enum DS {
    /// 8pt spacing grid.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
    /// Corner-radius scale — use these instead of ad-hoc values.
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
}

extension Color {
    // v3.2 "Modern Pop" structural tokens. Each is an asset colorset with a
    // light + dark appearance, so they adapt automatically. Use these at
    // container + card level instead of stark system backgrounds / white.
    /// App canvas — a soft cool off-white in light, the brand near-black in dark.
    static let appBackground = Color("AppBackground")
    /// Elevated card / sheet surface that lifts off `appBackground`.
    static let cardSurface   = Color("CardSurface")
    /// Hairline card / divider border.
    static let cardBorder    = Color("CardBorder")
    /// Primary text on `appBackground` / `cardSurface`.
    static let textPrimary   = Color("TextPrimary")
    /// Secondary / supporting text.
    static let textSecondary = Color("TextSecondary")
}

extension Font {
    /// Space Grotesk at an explicit size + weight (non-scaling; good for fixed
    /// chrome like tier badges). Maps weights onto the four bundled instances.
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "SpaceGrotesk-Bold"
        case .semibold:             name = "SpaceGrotesk-SemiBold"
        case .medium:               name = "SpaceGrotesk-Medium"
        default:                    name = "SpaceGrotesk-Regular"
        }
        return .custom(name, size: size)
    }

    // Semantic display tokens — Space Grotesk, scaling with Dynamic Type.
    static let sLargeTitle = Font.custom("SpaceGrotesk-Bold", size: 34, relativeTo: .largeTitle)
    static let sTitle      = Font.custom("SpaceGrotesk-Bold", size: 26, relativeTo: .title)
    static let sHeadline   = Font.custom("SpaceGrotesk-SemiBold", size: 20, relativeTo: .headline)
}

extension View {
    /// v3.2 "Modern Pop": the warm app canvas behind a tab's scrollable
    /// content. Hides the default grouped List/Form background and paints the
    /// `appBackground` token so white `cardSurface` rows lift off it. Harmless
    /// on a plain ScrollView (which is already transparent). Apply to the
    /// List / Form / ScrollView at the root of each tab.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
    }
}
