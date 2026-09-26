import Foundation

/// What a scene restores after a relaunch: the selected tab, the detail
/// screens open on Home and the SwiftUI tabs' navigation paths. Saved and
/// restored through the scene's `NSUserActivity`, UIKit's scene state
/// restoration (`stateRestorationActivity(for:)`); SwiftUI's
/// `@SceneStorage` does not work in a UIKit scene.
@MainActor
final class SceneRestoration {
    /// Listed in Info.plist under `NSUserActivityTypes`.
    static let activityType = "com.scriptercarft.AppleVideos.restoration"

    private enum Key {
        static let tab = "tab"
        static let homeRoutes = "homeRoutes"
        static let paths = "paths"
    }

    let selectedTab: String?
    let homeRoutes: [VideoRoute]
    /// Encoded `NavigationPath.CodableRepresentation`s by stack ID, kept
    /// current by `RestorableNavigationStack`.
    var paths: [String: Data]

    init(activity: NSUserActivity?) {
        let info = activity?.activityType == Self.activityType ? activity?.userInfo : nil
        selectedTab = info?[Key.tab] as? String
        homeRoutes = (info?[Key.homeRoutes] as? Data)
            .flatMap { try? JSONDecoder().decode([VideoRoute].self, from: $0) } ?? []
        paths = info?[Key.paths] as? [String: Data] ?? [:]
    }

    /// The activity that restores the current state.
    func activity(selectedTab: String?, homeRoutes: [VideoRoute]) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        var info: [String: Any] = [Key.paths: paths]
        info[Key.tab] = selectedTab
        info[Key.homeRoutes] = try? JSONEncoder().encode(homeRoutes)
        activity.addUserInfoEntries(from: info)
        return activity
    }
}
