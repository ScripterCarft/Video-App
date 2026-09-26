import Foundation

/// What a scene restores after a relaunch: the selected tab and the screens
/// on each tab's stack. Saved and restored through the scene's
/// `NSUserActivity`, UIKit's scene state restoration
/// (`stateRestorationActivity(for:)`).
@MainActor
final class SceneRestoration {
    /// Listed in Info.plist under `NSUserActivityTypes`.
    static let activityType = "com.scriptercarft.AppleVideos.restoration"

    private enum Key {
        static let tab = "tab"
        static let stacks = "stacks"
    }

    let selectedTab: String?
    /// The routes on each tab's stack above its root, by tab.
    let stacks: [String: [AppRoute]]

    init(activity: NSUserActivity?) {
        let info = activity?.activityType == Self.activityType ? activity?.userInfo : nil
        selectedTab = info?[Key.tab] as? String
        stacks = (info?[Key.stacks] as? Data)
            .flatMap { try? JSONDecoder().decode([String: [AppRoute]].self, from: $0) } ?? [:]
    }

    /// The activity that restores the current state.
    func activity(selectedTab: String?, stacks: [String: [AppRoute]]) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        var info: [String: Any] = [:]
        info[Key.tab] = selectedTab
        info[Key.stacks] = try? JSONEncoder().encode(stacks)
        activity.addUserInfoEntries(from: info)
        return activity
    }
}
