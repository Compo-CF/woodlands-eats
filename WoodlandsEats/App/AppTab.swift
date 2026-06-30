import SwiftUI
import Observation

/// v1.5: tab identity enum. Used by ContentView's TabView selection
/// binding so child views can programmatically switch tabs (e.g., the
/// rank icon shortcut in Map/Browse → Profile).
enum AppTab: Hashable {
    case map, browse, myTiers, community, profile
}

/// v1.5: programmatic-tab-switching channel. ContentView constructs
/// one and injects it via @Environment. Child views read it and set
/// `selectedTab` to switch tabs from anywhere in the view hierarchy.
///
/// Implemented as an @Observable class rather than an EnvironmentKey
/// + Binding pair because Swift's type checker has trouble inferring
/// the key-path type through generic Binding<T> in EnvironmentValues
/// extensions — the @Observable + Environment(Type.self) pattern
/// sidesteps that ambiguity cleanly on iOS 17+.
@Observable
final class TabRouter {
    var selectedTab: AppTab = .map
}
