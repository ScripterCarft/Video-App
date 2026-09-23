# Apple Videos

A native personal video app for iOS 27, built with SwiftUI.

## Naming

- **Home Screen display name:** Videos
- **Internal project, target, product, and App Store working name:** Apple Videos
- **Bundle identifier:** unchanged

Only `CFBundleDisplayName` is shortened. Do not rename the Xcode target or Swift module to match the Home Screen label.

## Current product behavior

- Four native tabs: Home, Explore, Library, and Search
- Curated Home feed and public YouTube search
- Saved videos, playlists, and Continue Watching stored on device
- Native navigation, context menus, sharing, haptics, and zoom transitions
- A modular playback resolver behind `PlaybackResolving`
- Native `AVPlayer` / `AVPlayerViewController` playback when the resolver supplies a compatible stream
- Embedded YouTube playback remains available as a fallback

The YouTube and Innertube representations stay inside the service and resolver layers. Views and the rest of the application must depend on app models and resolver protocols, never on raw Innertube response types. Resolved playback URLs are short-lived and must not be persisted. They are also bound to the client network address, so the resolver reuses a resolved source for at most ten minutes, and closing a player whose item failed invalidates it. `YouTubeWebConfiguration` loads the Innertube web configuration (API key, client version, visitor data) once, is warmed up at launch and is shared by search, details and playback; a rejected request invalidates it so the next request loads it again.

## Project structure

- `App/`: app entry point, app delegate (audio session, orientation) and launch-time setup
- `Models/`: provider-neutral app models
- `Services/`: YouTube search and details, the on-device library and artwork loading
- `Services/Playback/`: the provider-neutral resolver contract, the YouTube resolver and `NativePlayback`
- `Views/Screens/`: one file per tab plus the video detail screen
- `Views/Player/`: the embedded YouTube fallback
- `Views/Components/`: shared views, including `VideoLink`
- `Support/`: small Foundation extensions

Every tab owns one `NavigationStack` and registers the video detail destination once with `videoDestination(transition:)` on its root. Links use `VideoLink`, which scopes the zoom-transition ID to the section a video was tapped in. Do not add further `navigationDestination(for:)` declarations for videos inside pushed screens.

## Continue Watching

`LibraryStore` owns Continue Watching and persists it under `apple-videos.recent`.

- A video is added when its player closes after at least ten seconds of actual playback.
- The list is deduplicated and limited to the eight most recent videos when it is loaded and whenever a video is marked as watched.
- The app refreshes the saved entries once per launch, from `AppleVideosApp.init`, concurrently through `YouTubeService.refreshedVideo`.
- Title, channel, duration, description, views, thumbnail, badges, and publication information are refreshed when YouTube supplies them.
- Videos store their publish date (`publishedAt`). Relative labels such as “8 days ago” are formatted at display time, so they never go stale. Search results carry an approximate date derived from YouTube's relative text; opening a video's detail screen stores the exact date and current metadata in every library list that contains it.
- Refresh preserves the original order. If one request fails or omits a field, the stored value for that video is retained.
- The normalized, refreshed list is written back to local storage.


## Playback

Playback follows Apple's AVKit guidance:

- The audio session category (`.playback`, `.moviePlayback`) is set once in `application(_:didFinishLaunchingWithOptions:)`. AVPlayer activates the session when playback starts.
- A video's stream is resolved when its detail screen opens (and for the featured video on Home), so Play usually finds it cached.
- `NativePlayback` (`Services/Playback/NativePlayback.swift`) creates the `AVPlayer` and presents `AVPlayerViewController` modally from the window's top view controller right away and starts playback when the presentation completes; AVKit shows its own loading state. No SwiftUI view hosts, observes or updates the player while it is on screen. A stream that fails before playback starts dismisses the player and shows the embedded fallback.
- The player keeps AVKit's default presentation style, backdrop, controls, swipe-down dismissal, AirPlay and Picture in Picture.
- The app supplies Now Playing metadata through `externalMetadata` and caps HLS at 720p on expensive (cellular) networks with `preferredMaximumResolutionForExpensiveNetworks`. On other networks AVPlayer's adaptive bitrate selection chooses the quality.
- Watch time is counted with `addPeriodicTimeObserver`; only advancing playback counts, seeks and stalls do not.
- Dismissal is reported by `playerViewController(_:willEndFullScreenPresentationWithAnimationCoordinator:)`. The detail screen hears back exactly once, after the player or Picture in Picture has closed. Restoring from Picture in Picture presents the same controller again.
- The app is portrait only; only `AVPlayerViewController` may rotate (`AppDelegate.application(_:supportedInterfaceOrientationsFor:)`).
- When the resolver has no compatible source, the embedded YouTube player is shown as a separate full-screen SwiftUI overlay.

Do not add a custom pan gesture, transform private AVKit subviews, or stack a second player overlay over Apple's controls. Keep player changes on public AVKit APIs and validate them on a physical device. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for the open interactive-dismissal backdrop issue.

## Generate and build

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild \
  -project AppleVideos.xcodeproj \
  -scheme AppleVideos \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions builds the Debug configuration for the simulator and the Release configuration for devices on every push and pull request. The Debug build ensures `#if DEBUG` code keeps compiling.

## Device installation

An iPhone build must be signed with an Apple development or distribution certificate and a provisioning profile. Signing secrets must never be committed to the repository.
