import SwiftUI

/// v1.5: tab identity enum. Used by ContentView's TabView selection
/// binding so child views can programmatically switch tabs (e.g., the
/// rank icon shortcut in Map/Browse → Profile).
enum AppTab: Hashable {
    case map, browse, myTiers, community, profile
}

private struct AppTabSelectionKey: EnvironmentKey {
    /// Default is a no-op binding so views can read the environment
    /// without crashing in previews or detached test contexts. Real
    /// usage replaces this with ContentView's @State binding.
    static let defaultValue: Binding<AppTab> = .constant(.map)
}

extension EnvironmentValues {
    /// v1.5: programmatic-tab-switching channel. Set the binding's
    /// value from any child view to switch tabs. Used by MapTabView
    /// and ListTabView's rank-icon shortcut to jump to Profile.
    var tabSelection: Binding<AppTab> {
        get { self[AppTabSelectionKey.self] }
        set { self[AppTabSelectionKey.self] = newValue }
    }
}
