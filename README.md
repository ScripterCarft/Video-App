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

The YouTube and Innertube representations stay inside the service and resolver layers. Views and the rest of the application must depend on app models and resolver protocols, never on raw Innertube response types. Resolved playback URLs are short-lived and must not be persisted. They are also bound to the client network address, so the resolver reuses a resolved source for at most ten minutes, and closing a player whose item failed invalidates it. Both Innertube clients drop their cached configuration after a failed request and bootstrap again on the next one.

## Project structure

- `App/`: app entry point and shared URL cache setup
- `Models/`: provider-neutral app models
- `Services/`: YouTube search/details, the playback resolver, the on-device library and artwork loading
- `Views/Screens/`: one file per tab plus the video detail screen
- `Views/Player/`: native AVKit presentation and the embedded YouTube fallback
- `Views/Components/`: shared views, including `VideoLink`
- `Support/`: small Foundation extensions

Every tab owns one `NavigationStack` and registers the video detail destination once with `videoDestination(transition:)` on its root. Links use `VideoLink`, which scopes the zoom-transition ID to the section a video was tapped in. Do not add further `navigationDestination(for:)` declarations for videos inside pushed screens.

## Continue Watching

`LibraryStore` owns Continue Watching and persists it under `apple-videos.recent`.

- Playback is added only after the existing watch threshold is reached.
- The list is deduplicated and limited to the eight most recent videos when it is loaded and whenever a video is marked as watched.
- On app launch, the saved entries are refreshed concurrently through `YouTubeService.refreshedVideo`.
- Title, channel, duration, description, views, thumbnail, badges, and publication information are refreshed when YouTube supplies them.
- The exact YouTube publication date is converted to a localized relative label during refresh, so labels such as “8 days ago” advance on later launches.
- Refresh preserves the original order. If one request fails or omits a field, the stored value for that video is retained.
- The normalized, refreshed list is written back to local storage.

The service coalesces simultaneous requests for YouTube's web configuration into a single in-flight task. Refreshing eight videos therefore does not bootstrap the same configuration eight times.

## Playback status and handoff

Native playback is owned by `NativePlayback` (`Views/Player/NativePlayback.swift`). The Play button resolves the source; `NativePlayback` then creates the `AVPlayer` and presents `AVPlayerViewController` from the window's top view controller, the way a UIKit app would. No SwiftUI view hosts, observes or updates the player while it is on screen, so nothing in the app re-renders under AVKit's interactive dismissal. The player keeps AVKit's default modal presentation style, background and controls; AVKit owns the backdrop and the swipe-down dismissal. The app only supplies Now Playing metadata, the audio session and the cellular HLS quality preference. The embedded YouTube fallback is a separate SwiftUI overlay with its own full-screen surface.

`NativePlayback` learns about a completed dismissal from `playerViewController(_:willEndFullScreenPresentationWithAnimationCoordinator:)` and reports back to the detail screen exactly once, after the player has closed or Picture in Picture has been closed. Watch history is recorded at that point once ten seconds of actual playback were reached. Restoring from Picture in Picture presents the same controller again from the top view controller.

The following work still needs physical-device validation before the player presentation can be considered stable:

- Native swipe-down dismissal, Picture in Picture restoration, rotation, AirPlay, and system controls across iPhone orientations
- Any lock-screen `MPNowPlayingInfoCenter` bridge beyond AVFoundation's existing metadata
- Any player information panel or additional transport-control customization

Do not add a custom pan gesture, transform private AVKit subviews, or stack a second player overlay over Apple's controls. Keep player changes on public AVKit APIs and validate them on a physical device.

Search-tab minimization and a bottom accessory are also deferred and are not part of this change.

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
