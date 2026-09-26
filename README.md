# Apple Videos

A native personal video app for iOS 27, built in modern UIKit: a scene
delegate, a tab bar controller with `UITab`s, and view controllers with
compositional collection views, diffable data sources, content
configurations and observation tracking (`updateProperties()`). Only the
embedded web player fallback is SwiftUI.

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

- `App/`: the app delegate (entry point, launch-time setup, audio session, orientation), the scene delegate and the scene's state restoration (`SceneRestoration`)
- `Views/Navigation/AppTabBarController.swift`: the tab bar (`UITab`s) and the download failure alert
- `Models/`: value models used by the app (`Video`, `PlaybackProgress`)
- `Persistence/Models/`: SwiftData records (`StoredVideo`, `WatchProgress`), with their existing schema names and fields
- `Persistence/`: opening the durable database, atomic writes and storage error state (`LibraryDatabase`, `LibraryStorageStatus`)
- `Persistence/Migrations/`: importing legacy UserDefaults data and moving old watch positions
- `Services/YouTube/`: YouTube metadata and shared web configuration
- `Services/Networking/`: network-path information and request-level data permissions
- `Services/Library/`: the on-device library and video catalog
- `Services/Details/`: retryable detail loading, independent of UIKit and playback ownership
- `Services/Artwork/`: shared image requests, caching, preparation and Now Playing JPEG generation
- `Services/Playback/`: the provider-neutral resolver contract, the YouTube resolver and `NativePlayback`
- `Services/Downloads/`: offline downloads
- `Services/Search/`: observable search state and request ownership; its UIKit list presentation stays in `Views/Collection/SearchResults+ListState.swift`
- `Tests/Search/`: controlled search ordering and detail retry/cancellation checks (`bash Tests/Search/run.sh` on a Mac)
- `Tests/Downloads/`: deterministic cancellation/restart checks against the production preparation coordinator (`bash Tests/Downloads/run.sh` on a Mac)
- `Views/Home/`: the UIKit Home screen (`HomeViewController`) and its Featured and Spotlight cards
- `Views/Detail/`: the UIKit video detail screen, blue test artwork stage, loading and retry cells (hero removed for a later step-by-step rebuild)
- `Views/Artwork/`: shared card image loading, reuse protection and transitions
- `Views/Collection/`: shared video cards, shelf/list layouts, prefetching and context menus
- `Views/Components/`: shared system Play-button and unavailable-state configurations
- `Views/Downloads/`: the download bar-button presentation
- `Views/Sharing/`: the native share-sheet item
- `Views/Navigation/`: routes (`VideoRoute`, `AppRoute`) and `VideoNavigator`, which pushes screens and opens videos with UIKit's zoom transition
- `Views/Screens/`: Explore, Search, Library and the reusable video-list screen
- `Views/Player/`: the embedded YouTube fallback (SwiftUI)
- `Views/Storage/`: native startup recovery when the library cannot be opened or migrated
- `Support/`: small Foundation extensions

Navigation carries only a video's ID (`VideoRoute`); the detail screen reads the video from `VideoCatalog`. Every tab is a UIKit navigation controller with its own `VideoNavigator`: it pushes `VideoDetailViewController` with `preferredTransition = .zoom` from the tapped card's artwork, and other screens (a topic's results, a Library list) from their `AppRoute`. After a relaunch the scene restores the selected tab and each tab's screens through its state restoration activity.

Artwork comes from `ArtworkLoader`: shared downloads, HTTP caching, downsampling to the drawn size and an in-memory cache. A video keeps the best 16:9 thumbnail YouTube lists; a 1280 image, once known, is never replaced by a smaller one (Up Next lists only small ones), and the detail screen loads the 1280 image as soon as the video's details list it.

An available HTTP-cache response is displayed immediately, including after its
freshness lifetime, while URLSession checks it under the normal HTTP cache
policy. Stale ETag responses can be revalidated without downloading the image
again. Updated bytes become visible when the prepared memory entry is next
rebuilt; existing cards do not change beneath the user. The prepared cache keys
include candidates, cropping and pixel width. NSCache has a 64 MiB cost target
and a 200-image count target; these are advisory eviction limits.

`VideoCollectionViewController` uses UIKit's data-prefetch callbacks for Home,
Up Next, Explore and video lists. It starts at most two speculative requests per
screen, uses the same image size as the cards, cancels obsolete work and clears
index-path hints before replacing a snapshot. If a card joins a prefetch, its
shared download survives cancellation of the speculative request. Low Data
Mode disables speculative image loads.

Card and Featured artwork uses a plain gray placeholder without a symbol.
Memory-cache hits display immediately; asynchronous deliveries use UIKit's
cross-dissolve only while on screen and with Reduce Motion off. Up Next shows
a system header and activity indicator while waiting, then inserts its cards
using the diffable data source; an empty result removes the section. Now Playing
artwork is rendered and JPEG-encoded away from the main actor with `@concurrent`.

## Saved, History, and Watchlist

`LibraryStore` owns Saved, History and the Watchlist, stored in SwiftData with one `StoredVideo` per video and one `WatchProgress` per started video (`Persistence/Models/`). After every successful save of the shared context it reloads its lists synchronously and publishes them as plain values; a record is deleted once no list, progress or download needs it. Home shows the Watchlist under the title Continue Watching.

### Storage failure and recovery

The store keeps its existing default disk location. An opening failure never
substitutes an in-memory library or deletes the store: the scene shows a native
Library Unavailable screen with Try Again. Library screens are created only
after opening, migrations and initial reads succeed. Background download
sessions still reconnect even if the library is unavailable.

All database writes use a synchronous main-actor `LibraryDatabase.transaction`.
Autosave is disabled; a changed context is explicitly saved and any fetch or
save failure rolls the operation back. Fetch failures are reported and retain
the last displayed value snapshots. Storage notices wait while another modal
owns the screen and repeated failures share a notice until acknowledged and a
later write succeeds.

Legacy imports reject malformed payloads, commit to disk before removing only
the imported UserDefaults keys, and can run again after an interruption without
overwriting newer progress. Undecoded old playlist payloads remain untouched.
Completed downloads keep their recovery entry until the database save succeeds;
the app retries those commits on activation. Removing a download commits its
library change before deleting the package, so a failed database save leaves
the existing offline file intact.

Short persistence regression checks live in `Tests/Persistence/`, outside the
application target. On a Mac, run `bash Tests/Persistence/run.sh`. Their separate
CI workflow runs only when the relevant storage files change, without a
simulator; the app build remains Debug simulator + Release device.

- Native playback commits History and the saved position in one SwiftData transaction once playback qualifies (ten seconds of playback, continuing a saved position, or reaching the end). AVFoundation's `timeJumpedNotification` resets watch-time sampling on seeks. Dismissing full screen publishes the committed state to the visible lists; a restart reads it directly without needing that callback. History is deduplicated and keeps the 50 most recent videos. The embedded fallback records History after ten seconds but does not store resume positions; native streams without a finite duration record History on close.
- The Watchlist holds videos added by hand plus History videos with resumable progress, most recent activity first. Reaching 95% removes the saved position and manual Watchlist membership in that same transaction. The change becomes visible on full-screen dismissal, during mini playback, or on app restart. Mark as Watched and Remove from Watchlist also clear progress. Remove from Recently Watched takes a video out of History and clears its progress.
- Playlists were removed. On first launch their stored data is migrated once: Watch Later into the Watchlist, other playlists into Saved.
- At launch, from `AppDelegate`, only the first eight Watchlist videos are refreshed. Saved and History refresh when opened. Each video is successfully refreshed at most once per launch, four at a time, through `YouTubeService.refreshedVideo`; failures remain retryable and stored data stays on screen until fresh data replaces it.
- Title, channel, duration, description, views, thumbnail, badges, and publication information are refreshed when YouTube supplies them.
- Videos store their publish date (`publishedAt`). Relative labels such as “8 days ago” are formatted at display time, so they never go stale. Search results carry an approximate date derived from YouTube's relative text; opening a video's detail screen stores the exact date and current metadata in every library list that contains it.
- Refresh preserves the original order. If one request fails or omits a field, the stored value for that video is retained.
- The normalized, refreshed list is written back to local storage.

## Playback

### Network use and recovery

Streaming's Use Mobile Data controls native stream resolution and AVURLAsset
media access; browsing, search and visible thumbnails remain available. Cached
offline packages bypass the streaming restriction. Download Options separately
control background media transfers (their small preparation/metadata requests
still use the current connection).

Optional configuration warmup, launch metadata refresh, stream/artwork prefetch
and cached-artwork revalidation refuse Low Data Mode at the URLRequest level.
Visible artwork may use smaller candidates. Cached data is reused immediately.
Resolver/configuration in-flight work is separated by network permission so an
explicit request cannot inherit an optional request's refusal, or vice versa;
successful cached content remains reusable. AVPlayer quality/buffer preferences
are updated when the network path changes.

The web fallback closes when a forbidden cellular path is observed and pauses
all media when dismantled. This is reactive: WebKit does not give the app the
same AVURLAsset-level control over the embedded player's media requests. Do not
claim that route detection guarantees zero cellular bytes for the fallback.

Detail loading preserves successful steps, including an empty Up Next result.
Failures show Try Again using UIKit, including when restoring an unknown video.
Retry loads only missing steps; cancellation never publishes a late response.
The Featured Play button uses its content size with larger horizontal padding,
a single-line title and a vertical button/duration arrangement at accessibility
text sizes. List updates respect Reduce Motion; VoiceOver reads remaining time
in full units and announces downloaded cards.

Playback follows Apple's AVKit guidance:

- The audio session category (`.playback`, `.moviePlayback`) is set once in `application(_:didFinishLaunchingWithOptions:)`. AVPlayer activates the session when playback starts.
- A video's stream is resolved when its detail screen opens (and for the featured video on Home), so Play usually finds it cached.
- `NativePlayback` (`Services/Playback/NativePlayback.swift`) creates the `AVPlayer` and presents `AVPlayerViewController` modally from the window's top view controller right away and starts playback when the presentation completes; AVKit shows its own loading state. No SwiftUI view hosts, observes or updates the player while it is on screen. A stream that fails before playback starts dismisses the player and shows the embedded fallback.
- The player keeps AVKit's default presentation style, backdrop, controls, swipe-down dismissal, AirPlay and Picture in Picture.
- The app supplies Now Playing metadata through `externalMetadata`.
- Streaming Options live in the Settings app (Settings > Apps > Videos, `Settings.bundle`, read by `StreamingSettings`): Use Mobile Data, Mobile Data (High Quality / Automatic) and Wi-Fi (High Quality / Data Saver). Automatic and Data Saver cap HLS at 720p (`preferredMaximumResolutionForExpensiveNetworks` / `preferredMaximumResolution`); High Quality leaves the choice to AVPlayer's adaptive bitrate selection, which plays H.264 up to 1080p. Mobile data, Data Saver and Low Data Mode limit the forward buffer to 60 s. With Use Mobile Data off, Play shows an alert on mobile data and the asset disallows cellular access.
- Watch time is counted with `addPeriodicTimeObserver`; only advancing playback counts, seeks and stalls do not.
- Watch progress is saved per video on device (`LibraryStore`, in SwiftData, up to 200 videos): every five seconds while playing, and immediately on pause, at the end, when the player closes and when the app enters the background. After a crash at most the last few seconds are lost. Positions under ten seconds or past 95 % are not kept. Play resumes at the saved position: the seek is issued as soon as the item is ready and playback starts only after it finishes, so the first frame shown is the saved position, and Play buttons show the play symbol, a progress gauge and the remaining time instead of the word Play. Home's Featured provides the Play button; the detail hero has been removed at the user's request for a later step-by-step rebuild. Native playback defers publishing progress until the session ends.
- Dismissal is reported by `playerViewController(_:willEndFullScreenPresentationWithAnimationCoordinator:)`. Completing dismissal closes playback unless PiP is starting or active. Cancelled gestures leave playback intact. PiP restoration reuses the same controller and player; closing PiP ends the session once. The mini player has been removed. Lock/background behavior uses AVPlayer's `.pauses` policy. See [Playback lifecycle](Docs/PlaybackLifecycle.md) for the archived experiment, transition rules, limitations and device checks.
- The app is portrait only; only `AVPlayerViewController` may rotate (`AppDelegate.application(_:supportedInterfaceOrientationsFor:)`).
- When the resolver has no compatible source, the embedded YouTube player (SwiftUI, `EmbeddedPlayerScreen`) is presented full screen.

## Downloads

`DownloadManager` (`Services/Downloads`) downloads videos for offline playback the way the TV app does:

- Background `AVAssetDownloadURLSession`s, one Wi-Fi only and one allowing mobile data. Downloads continue while the app is suspended or closed; the app reconnects at launch and completes the system's background events (`AppDelegate`).
- Before each download a fresh stream link is resolved (`DownloadURLProviding`, today `DirectDownloadURLProvider`). The best H.264 variant up to the chosen quality is pinned with `AVAssetVariantQualifier(variant:)`; VP9 variants are never downloaded because AVFoundation cannot play them.
- Only complete packages are kept. Stopping, failing or an interrupted download deletes the partial package. Finished downloads are stored on the video's `StoredVideo` record (`downloadPath`), so they show and play offline; packages that disappear are dropped at launch.
- Download Options in the Settings app: Use Mobile Data (off by default; downloads then wait for Wi-Fi) and Wi-Fi High Quality (1080p) / Fast Downloads (720p, default). Mobile data always uses 720p.
- A downloaded video plays from its package, without network or data. The detail button of a downloaded video offers Download Again to Renew and Remove Download; Library > Downloaded offers Remove All.
- Known limitation: YouTube refuses the direct system download for many videos with HTTP 401, although the same requests succeed from the app. See CLAUDE.md for what was ruled out.

Do not add a custom pan gesture, transform private AVKit subviews, or stack a second player overlay over Apple's controls. Keep player changes on public AVKit APIs and validate them on a physical device. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for the interactive-dismissal backdrop issue, resolved by building with the iOS 27 SDK.

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

Building needs Xcode 27 (the deployment target is iOS 27). GitHub Actions builds on the `xcode-27` runner image the Debug configuration for the simulator and the Release configuration for devices on every push and pull request, and uploads an unsigned IPA. The Debug build ensures `#if DEBUG` code keeps compiling.

## Device installation

An iPhone build must be signed with an Apple development or distribution certificate and a provisioning profile. Signing secrets must never be committed to the repository.
