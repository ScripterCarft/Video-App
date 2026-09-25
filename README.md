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
- Saved videos, History, and the Watchlist stored on device
- Offline downloads (H.264 HLS through a background `AVAssetDownloadURLSession`), see Downloads
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

## Saved, History, and Watchlist

`LibraryStore` owns Saved, History (`apple-videos.recent`) and the Watchlist (`apple-videos.watchlist`). Home shows the Watchlist under the title Continue Watching.

- A video is added to History when its player closes after at least ten seconds of actual playback. History is deduplicated and keeps the 50 most recent videos.
- The Watchlist holds videos added by hand plus History videos with resumable progress, most recent activity first. A video leaves it when played to the end (applied when the player closes), on Mark as Watched, or on Remove from Watchlist; the last two also clear its progress. Remove from Recently Watched takes a video out of History and clears its progress.
- Playlists were removed. On first launch their stored data is migrated once: Watch Later into the Watchlist, other playlists into Saved.
- At launch, from `AppleVideosApp.init`, only the first eight Watchlist videos are refreshed. Saved and History refresh when opened. Each video is requested at most once per launch, four at a time, through `YouTubeService.refreshedVideo`; stored data stays on screen until fresh data replaces it.
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
- The app supplies Now Playing metadata through `externalMetadata`.
- Streaming Options live in the Settings app (Settings > Apps > Videos, `Settings.bundle`, read by `StreamingSettings`): Use Mobile Data, Mobile Data (High Quality / Automatic) and Wi-Fi (High Quality / Data Saver). Automatic and Data Saver cap HLS at 720p (`preferredMaximumResolutionForExpensiveNetworks` / `preferredMaximumResolution`); High Quality leaves the choice to AVPlayer's adaptive bitrate selection, which plays H.264 up to 1080p. Mobile data, Data Saver and Low Data Mode limit the forward buffer to 60 s. With Use Mobile Data off, Play shows an alert on mobile data and the asset disallows cellular access.
- Watch time is counted with `addPeriodicTimeObserver`; only advancing playback counts, seeks and stalls do not.
- Watch progress is saved per video on device (`LibraryStore`, `apple-videos.progress`, up to 200 videos): every five seconds while playing, and immediately on pause, at the end, when the player closes and when the app enters the background. After a crash at most the last few seconds are lost. Positions under ten seconds or past 95 % are not kept. Play resumes at the saved position: the seek is issued as soon as the item is ready and playback starts only after it finishes, so the first frame shown is the saved position, and Play buttons (detail screen and the Home hero) show the play symbol, a progress gauge and the remaining time instead of the word Play. During playback progress is only written to storage; the UI picks it up when the player closes.
- Dismissal is reported by `playerViewController(_:willEndFullScreenPresentationWithAnimationCoordinator:)`. The detail screen hears back exactly once, after the player or Picture in Picture has closed. Restoring from Picture in Picture presents the same controller again.
- The app is portrait only; only `AVPlayerViewController` may rotate (`AppDelegate.application(_:supportedInterfaceOrientationsFor:)`).
- When the resolver has no compatible source, the embedded YouTube player is shown as a separate full-screen SwiftUI overlay.

## Downloads

`DownloadManager` (`Services/Downloads`) downloads videos for offline playback the way the TV app does:

- Background `AVAssetDownloadURLSession`s, one Wi-Fi only and one allowing mobile data. Downloads continue while the app is suspended or closed; the app reconnects at launch and completes the system's background events (`AppDelegate`).
- Before each download a fresh stream link is resolved (`DownloadURLProviding`, today `DirectDownloadURLProvider`). The best H.264 variant up to the chosen quality is pinned with `AVAssetVariantQualifier(variant:)`; VP9 variants are never downloaded because AVFoundation cannot play them.
- Only complete packages are kept. Stopping, failing or an interrupted download deletes the partial package. Finished downloads are stored under `apple-videos.downloads` with their video metadata, so they show and play offline; packages that disappear are dropped at launch.
- Download Options in the Settings app: Use Mobile Data (off by default; downloads then wait for Wi-Fi) and Wi-Fi High Quality (1080p) / Fast Downloads (720p, default). Mobile data always uses 720p.
- A downloaded video plays from its package, without network or data. The detail button of a downloaded video offers Download Again to Renew and Remove Download; Library > Downloaded offers Remove All.
- Known limitation: YouTube refuses the direct system download for many videos with HTTP 401, although the same requests succeed from the app. See CLAUDE.md for what was ruled out.

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
