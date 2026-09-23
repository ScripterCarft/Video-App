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

The YouTube and Innertube representations stay inside the service and resolver layers. Views and the rest of the application must depend on app models and resolver protocols, never on raw Innertube response types. Resolved playback URLs are short-lived and must not be persisted.

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

Native playback presents `AVPlayerViewController` modally from a transparent UIKit host attached to the video detail screen. The presentation uses `overFullScreen` so UIKit keeps that detail screen in its view hierarchy throughout an interactive dismissal. The player's outer view is nonopaque but black during ordinary playback; its background animates to clear alongside AVKit's interactive dismissal and returns to black if the gesture is cancelled. This preserves black letterboxing while revealing the detail screen during the gesture. The app does not place a black loading screen behind AVKit. The Play button indicates source resolution before the player exists; AVKit handles loading and buffering once the stream reaches the player. The embedded YouTube fallback retains its own full-screen surface. AVKit owns the video controls and full-screen dismissal. The host handles Picture in Picture restoration and returns to the video detail screen after dismissal. There are no custom native player gestures or controls. Metadata handoff, background audio, and the cellular HLS quality preference remain in place.

The host presents the native controller once and starts playback only after presentation completes. If SwiftUI restarts the source-resolution task during an interactive transition, it reuses the existing player. A cancelled dismissal does not create another player; a completed dismissal releases the player host.

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

GitHub Actions performs the same build for every push and pull request.

## Device installation

An iPhone build must be signed with an Apple development or distribution certificate and a provisioning profile. Signing secrets must never be committed to the repository.
