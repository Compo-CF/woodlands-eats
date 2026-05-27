import SwiftUI

struct ContentView: View {
    @Environment(CloudKitService.self) private var cloudKit

    var body: some View {
        TabView {
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tabItem { Label("Browse", systemImage: "fork.knife") }
            MyTiersView()
                .tabItem { Label("My Tiers", systemImage: "list.number") }
            CommunityTiersView()
                .tabItem { Label("Community", systemImage: "person.3.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task { await cloudKit.refreshClosureCounts() }
    }
}
