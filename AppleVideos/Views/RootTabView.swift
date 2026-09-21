import SwiftUI

enum AppTab: Hashable {
    case home
    case explore
    case library
    case search
}

struct RootTabView: View {
    @Environment(PlaybackStore.self) private var playback
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("Explore", systemImage: "safari", value: .explore) {
                ExploreView()
            }

            Tab("Library", systemImage: "rectangle.stack", value: .library) {
                LibraryView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView()
            }
        }
        .tabViewBottomAccessory(isEnabled: playback.currentVideo != nil && !playback.isExpanded) {
            MiniPlayerAccessory()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { playback.isExpanded },
                set: { playback.isExpanded = $0 }
            )
        ) {
            PlayerScreen()
        }
    }
}
