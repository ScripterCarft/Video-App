import SwiftUI

enum AppTab: Hashable {
    case home
    case explore
    case library
    case search
}

struct RootTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeTab()
            }

            Tab("Explore", systemImage: "safari", value: .explore) {
                ExploreView()
            }

            Tab("Library", systemImage: "rectangle.stack", value: .library) {
                LibraryView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }
        }
    }
}

