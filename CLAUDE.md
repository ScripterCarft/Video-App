# Apple Videos — working notes for Claude

Read this first in every new session. `README.md` describes behavior and
structure; this file holds the workflow, the principles behind decisions,
what is intentional, what was measured, and what is still open.
`KNOWN_ISSUES.md` holds the accepted player-dismissal bug.

## Workflow

- **Branch:** all work happens on `cleanup`. Merge into `main` only when the
  user explicitly says "merge". Before merging, ask whether to squash
  (`cleanup` contains many experiment and revert commits) or keep the
  individual commits; if single commits are kept, note that a51e717 alone
  does not compile (it uses `VideoCells.zoomSource` from c214758).
- **One change per commit**, with a message that says why. Experiments are
  labeled `EXPERIMENT` / `TEST (do not merge)` and reverted with `git revert`
  once they have answered their question.
- **Building:** the development machine is Windows: no Xcode, no Python, no
  local Swift compiler. GitHub Actions is the compiler. Every push builds
  Debug (simulator; keeps `#if DEBUG` code compiling) and Release (device)
  and uploads an unsigned IPA (`AppleVideos-iPhone`). CI runs on GitHub's
  `xcode-27` image (public preview, macOS 27, arm64, default Xcode 27.0 with
  the iOS 27 SDK; betas beside it are not used). Until 2026-09-26 it ran on
  `macos-26`, whose newest Xcode (26.6) has only the iOS 26.5 SDK: the app
  was linked against iOS 26 and no iOS 27 API compiled.
- **CI results:** read them through the public API
  (`https://api.github.com/repos/ScripterCarft/Video-App/actions/runs?per_page=1&branch=cleanup`).
  Unauthenticated calls are limited to 60 per hour: run **one** watcher at a
  time, stop it before starting another, poll about every 60–120 s. Job logs
  need admin rights; compiler errors appear as check-run annotations
  (`/check-runs/{job id}/annotations`). The user can also paste log lines.
  Never look for or read stored credentials.
- **Testing** happens only on the user's iPhone with the CI IPA (English
  device language). There are no unit tests in CI (a test job was tried on
  2026-09-26 and removed at the user's request: too slow). Say plainly that a
  change is untested on device, and give a short test list after each build.
- **Before building, think changes through and double-check them**: read the
  code a change touches, consider timing and every caller, and prefer one
  well-understood change over a change plus follow-up fixes. If a change
  needs guards to be safe, reconsider the change.
- **Shell pitfalls here:** `sed` replacement strings drop backslashes, which
  broke Swift key paths (`\.status`) and string interpolation (`\(x)`), and
  squashed multi-line inserts into one line. Use the Edit tool for anything
  with backslashes or several lines, and re-check the result. Write
  temporary files to the scratchpad, never into the repository.

## How the user wants to work

- Communicate in German. Be honest about uncertainty; never present a guess
  as a finding. When the cause is unknown, say so and propose a
  discriminating check instead of another speculative fix.
- When the user says "erst reden" / "erklär erst", explain and wait for the
  go-ahead before changing code.
- Verify against real data before optimizing (for example replaying the
  app's Innertube requests with `curl`, checking thumbnail headers and
  availability). Optimize only when certain.
- Do not remove features or UI without asking (removing "Up Next" once was
  wrong and was restored).
- Do not add custom styling where Apple already provides it (a custom
  context-menu preview shape was reverted because iOS already rounds it).

## Principles

- **Apple-native first.** Use public Apple APIs and follow the HIG and
  Apple's documented patterns. Close real gaps where the app deviates from
  what Apple does; do not add workarounds ("Lifehacks") or custom versions
  of things Apple already provides.
- **Efficient, not "reload everything".** Honor HTTP caching, Low Data Mode,
  shared downloads and one-time launch work.
- **Nothing in the app re-renders under AVKit.** Playback state is written
  to storage during playback and published to the UI when the player
  closes.

## Intentional design (keep; do not "clean up")

### Data and networking

- **Innertube is the core concept.** `YouTubeService` (WEB client) provides
  search, details, the full description and `publishDate`. The playback
  resolver (VISIONOS client) provides HLS/progressive streams, formats and
  caption tracks. Both requests per detail screen are required: verified
  with real responses, WEB returns `UNPLAYABLE` without streamingData or
  captions, VISIONOS has no microformat or publish date. Innertube
  specifics stay inside these two files and `YouTubeWebConfiguration`,
  which loads the API key, client version and visitor data once, is
  prewarmed at launch, shared by all Innertube requests and invalidated
  after rejected requests. Details are cached per video in memory.
- **Storage:** SwiftData (`LibraryDatabase`): one `StoredVideo` per video
  (metadata once, list membership, download path) and one `WatchProgress`
  per started video, kept apart so queries over videos do not update while
  a video plays. `LibraryStore` and `DownloadManager` do the writes and
  publish the lists other screens read as plain `[Video]` values, reloaded
  synchronously after every save of the shared context
  (`ModelContext.didSave`) and reassigned only when they changed. A record
  is deleted as soon as nothing needs it (`deleteIfUnused`). SwiftUI
  library screens use `@Query`. Earlier UserDefaults data and positions on
  video records are migrated once at launch. SwiftData's `ResultsObserver`
  was tried and rejected; see Measured findings.
- `Video` (value type for network results and routes) and `StoredVideo`
  (persistence) stay two types on purpose. `VideoCatalog` holds every video
  the app shows, by ID; navigation carries only IDs (`VideoRoute`).
- **Artwork:** YouTube lists `hq720`/`maxresdefault` exactly when they exist
  (verified), so `thumbnailURL` stores the best listed 16:9 image and
  `Video.artworkCandidates` requests the 1280 file only when listed. No
  size guessing. `ArtworkLoader` owns and shares downloads, uses the default
  cache policy (YouTube: `max-age=7200` + ETag), downsamples to the drawn
  width and keeps prepared images in an `NSCache`. The curated videos carry
  their known thumbnails. `Video.preferredThumbnail(known:new:)` is the one
  rule: a known URL stays unless the new one is 1280 and the known one is
  smaller. It applies to refreshes and to `VideoCatalog.remember`, so Up
  Next (which lists only `hqdefault`) never replaces a known 1280 image.
  Up Next cards stay at the cropped `hqdefault` (480×270, user's decision);
  the detail screen loads the 1280 image once the details list it
  (`DetailArtworkView.upgrade`, cross-dissolve, not in Low Data Mode).
- **Low Data Mode** (`NetworkConditions`): no 1280 artwork, no stream
  prefetch, HLS capped at 720p on every network, 60 s buffer; large images
  are requested with `allowsConstrainedNetworkAccess = false` and fall back
  quietly.
- `Video.publishedAt` stores the publish date; labels are formatted at
  display time. Search results get an approximate date from "N units ago".

### Playback

- `NativePlayback` presents `AVPlayerViewController` modally from the
  window's top view controller. No SwiftUI host view, no custom gestures,
  no private AVKit subviews. `PlaybackStarter` + `playbackPresentation(_:)`
  are the only way screens start playback. The embedded YouTube player
  (`EmbeddedPlayerScreen`) is the fallback when no native stream plays.
- Audio session category is set once at launch (`AppDelegate`). The app is
  portrait only; only `AVPlayerViewController` may rotate.
- **Streaming Options** (user's design) live in the Settings app
  (`Settings.bundle`, read by `StreamingSettings`): Use Mobile Data; Mobile
  Data High Quality / Automatic (default); Wi-Fi High Quality (default) /
  Data Saver. Automatic and Data Saver cap at 720p ("about 1 GB/hour";
  a hard 1 GB would force 480p for 60 fps videos, rejected). 60 s forward
  buffer on expensive networks, Data Saver and Low Data Mode; Wi-Fi High
  Quality keeps the automatic buffer (battery first). Use Mobile Data off
  blocks native and embedded playback on cellular with an alert.
- **Watch progress:** stored as `WatchProgress` (up to 200 entries), saved
  every 5 s and on pause, end, close and background; under 10 s or past
  95 % is not kept (thresholds chosen by us, not Apple). One rule (user's
  decision): a video counts as started after 10 s of actual playback
  (seeking does not count) or when it continues a saved position; only then
  is progress saved and the video added to History. Resume seeks on
  `readyToPlay` and starts playback only after the seek. The Play button
  shows the play symbol, a capsule `ProgressView` (8 pt) and the remaining
  time ("40m", "1m" under a minute).

### Library and downloads

- **Library** (user's decision): only Saved and History; playlists were
  removed (Watch Later migrated to the Watchlist, others to Saved). History
  stores the last 50 played videos with all shown metadata including the
  description (like Podcasts keeps episode data; only the video itself is
  not stored). The Watchlist = videos added by hand + started, unfinished
  History videos, newest activity first; Home shows it titled "Continue
  Watching". Finishing, Mark as Watched or Remove from Watchlist takes a
  video off (the latter two also clear its progress). Launch refreshes the
  first 8 Watchlist videos; Saved and History refresh when opened, once
  per video per launch, keeping stored data until fresh data replaces it.
- Library lists (Saved, Downloaded, History) are a plain `List` so
  removals from a card's context menu animate; with ScrollView +
  LazyVStack neighbors jumped under the returning menu preview. Rejected:
  delaying the change 0.4 s (timing hack, reverted).
- **Context menu** (user's layout): Download, Save/Unsave and Share side by
  side on top (`ControlGroup`); then Add to Watchlist (plus.circle) /
  Remove from Watchlist (minus.circle), Mark as Watched
  (rectangle.badge.checkmark, in Watchlist), Remove from Recently Watched
  (trash, in History, hidden while downloaded; the Library still says
  "History"). Only when downloaded: a separate, red Remove Download
  (trash), so there is never more than one trash item. UIKit screens use
  `VideoContextMenus`, SwiftUI screens `VideoLibraryActions`.
- **Downloads** (`Services/Downloads`, user's design, personal use; App
  Store guideline 5.2.3 forbids them): `DownloadManager` uses background
  `AVAssetDownloadURLSession`s (Wi-Fi only / with mobile data), pins the
  best H.264 variant with `AVAssetVariantQualifier(variant:)`, resolves a
  fresh link first, keeps only complete packages and plays them offline.
  Download Options in the Settings app: Use Mobile Data (default off, then
  downloads wait for Wi-Fi), Wi-Fi High Quality 1080p / Fast Downloads
  720p (default); mobile data always 720p. No HDR/Atmos line (YouTube HLS
  has neither). UI: detail bar button whose image is the progress ring (tap
  stops), a downloaded video's button opens a system menu with "Download
  Again to Renew" / red "Remove Download"; context menu Download / Stop,
  hidden once downloaded; download symbol beside the duration; Library >
  Downloaded and History each with Remove All.
- Renew/Remove on the detail screen and Remove All (Downloaded, History)
  are system `Menu`s with a section header as the explanation (rejected:
  custom gray popover, confirmation dialogs). History Remove All keeps
  downloaded videos.

### Screens (UIKit rebuild in progress)

- Home (`HomeViewController`) and the detail screen
  (`VideoDetailViewController`) are UIKit screens in a
  `VideoNavigationController` (Home tab, inside the SwiftUI `TabView`);
  videos open through `VideoNavigator` with UIKit's zoom
  (`preferredTransition = .zoom`) from the card's artwork; open detail
  screens are kept in `@SceneStorage` and restored. Each screen's
  collection view is its view: compositional layout, diffable data source,
  observable data read in `updateProperties()` (UIKit tracks it, iOS 26+).
  Home's title is inline-large (`largeTitleDisplayMode = .inline`,
  compared on device).
- Shelves (Continue Watching, Made for Tonight, Up Next) are one component:
  `VideoCells.shelfSection` (fixed sizes), `VideoCardConfiguration` (the
  UIKit card, a `UIContentConfiguration`), `VideoCells.headerConfiguration`
  (title only; section subtitles removed at the user's request) and
  `VideoContextMenus` (removals applied in `willEndContextMenuInteraction`;
  preview: the thumbnail alone in a padded bubble, UIKit preview
  controller, so the menu sits below; the card's artwork is the targeted
  highlight/dismissal preview).
- Text size and light/dark are not registered by hand: the section
  provider reads the layout environment's traits and `updateProperties()`
  reads the view's traits, and UIKit tracks both (automatic trait
  tracking; confirmed on device 2026-09-26). If card sizes ever stop
  following the text size, look here first: sizes are measured through
  `UIFont.preferredFont(forTextStyle:compatibleWith:)`, an indirect read.
- Never SwiftUI in fixed-size UIKit cells and no estimated sizes on these
  screens (proved on device): SwiftUI content in a cell gives way to the
  bars and home indicator wherever the cell lies, which squeezed cards and
  slid titles over them; with estimated sizes the layout recursed in
  `_updateVisibleCellsNow` until an assertion crashed the app (iOS 27).
  Featured and Spotlight on Home still break this rule (Open work).
- Search, Library and Explore are SwiftUI until they are rebuilt; they show
  the detail controller in a thin SwiftUI shell (`VideoDetailView`) with
  their own toolbar and zoom. Their navigation is value-based in every
  `NavigationStack`: `VideoLink` / `videoDestination(transition:)` for
  videos, route enums for library and Explore topics. Never mix
  view-destination `NavigationLink`s with value-based ones (that caused
  videos to pop right after opening).
- **Detail loading** (user's design): one task loads the details first;
  the description and info line are placeholders until then and everything
  appears in one animation; then Up Next, then the stream is prefetched
  (Play and stream badges). The loading keeps finished state, so nothing
  reloads when AVKit covers the screen; refreshed metadata is stored when
  the screen leaves, not while the player covers it. The Home featured
  video also prefetches its stream.
- **Detail scrolling** (user's design, like the TV app): the artwork is the
  collection view's background view, on the light blue TEST stage for now;
  a clear spacer (stage height minus the top inset; automatic insets, so the
  bar's scroll edge effect appears only after scrolling) and Up Next on a
  black page whose section background reaches two screen heights below the
  shelf. Scrolling down moves the artwork up at half speed; overshoot at
  the top scales it from its top edge (one transform per scroll frame).
  At the top a downward drag does not scroll (`DetailCollectionView`), so
  the zoom's swipe dismisses the screen. Download is a plain bar button
  item whose image is the progress ring; Share presents the share sheet
  from the bottom with the video's title and YouTube's own image.
- Detail screen: white bar tint and light status bar (whether the SwiftUI
  tab view passes the status bar style on is untested), keeps the system
  scroll edge effect (user: needed for legibility).
- Keep screens that take part in the zoom transition cheap to draw: the
  zoom redraws the live screen every frame. Proved on device: blurred,
  masked hero copies, text shadows, a material button and TextKit
  measuring made closing slow and left the app unresponsive (taps even
  hit the old Play button). No blurs, masks, shadows or materials on
  these screens without measuring.
- Removed on purpose: the empty Profile button (App Review rejects
  non-functional UI). "Up Next" stays at the user's request.
- Language mixing (UI English, YouTube texts in the device language) is left
  as is on the user's decision.

## Measured findings (keep; they explain decisions)

- **AVPlayer and YouTube HLS** (device, test build, reverted): AVPlayer plays
  only H.264 from YouTube's HLS; the VP9 variants (up to 4K) are not even
  recognized, so 1080p60 is the maximum and codec rewriting is pointless.
  720p60 averages 2.2–2.6 Mbit/s, 1080p60 4.3. YouTube encodes HD of 60 fps
  uploads only at 60 fps. The automatic buffer loaded 73–109 s ahead, a
  low-bitrate video entirely. AV1 exists only outside HLS (hardware decode
  from A17 Pro) and is not worth building now.
- **Download HTTP 401** (test builds, reverted): the direct system download
  gets HTTP 401 from YouTube for many videos, immediately, while the same
  requests from the app succeed. Ruled out: headers, cookies,
  IP/IPv4-vs-IPv6 and HTTP version (webhook.site capture, same for app,
  AVPlayer and download service), subtitles, VP9 in the playlist. A local
  pass-through proxy in the app (the app fetches every playlist and
  segment) downloads reliably. Cause unknown; `DownloadURLProviding` is
  the place to add that route. The user parked it.
- **Up Next thumbnails** (real `next` response, 2026-09-26): lockups list
  only `hqdefault` at 168×94 and 336×188; `hq720`/`maxresdefault` exist for
  those videos but are not listed. The app strips the query and crops the
  4:3 `hqdefault` (480×360) to 480×270.
- **SwiftData `ResultsObserver` (iOS 27), rejected** (iOS 27.0 simulator,
  2026-09-26): it updates its results asynchronously, about 10–30 ms (up to
  ~125 ms) after a save that touches the observed model, including saves of
  records outside its filter and the first save of a new `WatchProgress`,
  not for saving a changed `WatchProgress` or for unsaved changes. A UIKit
  view reading it in `updateProperties()` does update by itself. Until it
  refetches, it still lists a record deleted in that save, and reading any
  attribute of that record crashes ("Could not cast value of type
  'Optional<Any>' to 'String'"); such a record reports `isDeleted` before
  the save and only a missing `modelContext` after it.
  `withContinuousObservation(options: [.didSet])` (iOS 27, Apple's WWDC26
  pattern) calls back twice right after setup, and a callback between a
  save and the refetch read the deleted record too. Since the app deletes
  records when they leave their last list and reads lists at any time,
  this needed a deleted-record filter, a store lookup before downloads,
  and left a Download button flash and a double Home animation. The
  synchronous `ModelContext.didSave` reload has none of this and stays.
  `ResultsObserver` suits changes from outside the app (CloudKit, other
  processes), not a store whose own actions must show at once.
- **iOS 27 section provider observation tracking** (Apple's documentation):
  it only invalidates the *layout* (sizes, arrangement); which videos a
  shelf shows stays the diffable snapshot, applied in
  `updateProperties()`. Use it only where a section's layout depends on
  observable state.
- **Other iOS 27 APIs checked, available with the Xcode 27 SDK:**
  `UITabBarController.prominentTabIdentifier`,
  `UINavigationItem.barMinimizeBehavior`,
  `UIScene.extendStateRestoration()` / `completeStateRestoration()`,
  `UIMenuElement.subtitle`; AVKit's generated subtitles (on-device
  transcription of English audio and translation of English subtitles, no
  app code needed; whether they appear for YouTube's HLS is untested).
  No iOS 27 API loads or caches network images; Apple's way stays
  `URLSession` + `byPreparingThumbnail` + a cache, and
  `UICollectionViewDataSourcePrefetching` (not used yet) to start artwork
  downloads before cells appear.

## Open work

**The rebuild (current, user-approved plan).** Goal: the app feels like one
system, built the way Apple builds the TV and Podcasts apps; big rebuilds
are fine. User's decision (2026-09-26): rebuild in modern UIKit, screen by
screen, with iOS 26/27 features checked at every step. Done: Home and the
detail screen, the shared shelf, card and context menu, the detail
scrolling. Next steps, in the order agreed with the user (explain each
before building):

1. **Featured and Spotlight on Home in UIKit.** They are still SwiftUI in
   cells with estimated sizes, the pattern that squeezed and crashed
   elsewhere. Featured as its own content configuration (with the Play
   button, `UIButton.Configuration`), Spotlight as a
   `UIListContentConfiguration` (symbol, title, text) on a rounded
   `UIBackgroundConfiguration`; sizes computed, not estimated.
2. **The app shell in UIKit:** `UITabBarController` with `UITab` /
   `UISearchTab` instead of the SwiftUI `TabView`. Brings tab bar minimize
   on scroll and the bottom accessory for a mini player (iOS 26),
   `prominentTabIdentifier` and `barMinimizeBehavior` (iOS 27) where they
   fit, and makes the detail screen's light status bar reliable
   (`childForStatusBarStyle` is only honoured if every parent passes it on).
   Restoration moves from `@SceneStorage` to the scene's
   `stateRestorationActivity` with `UIScene.extendStateRestoration` for
   detail screens whose video must load first. Prefer per-screen bar
   appearance over the detail screen changing the shared bar's tint in
   `viewWillAppear` (Home resets it today).
3. **Search, Library and Explore in UIKit:** collection views with the same
   card and menu; Library lists with `UICollectionLayoutListConfiguration`
   and its swipe actions; Search as a normal tab in the bar, not separated,
   with recent searches; the Library's entry screen stays the compact list
   with icons. Afterwards remove the SwiftUI leftovers: `VideoCard`,
   `VideoArtwork`, `VideoHeroArtwork`, `SectionHeader`, `VideoLink`,
   `RestorableNavigationStack`, the `VideoDetailView` shell,
   `DownloadToolbarButton`, `DownloadProgressRing`, `VideoLibraryActions`
   (`HomeCards`, `PlayButtonContent` and `VideoHeroArtwork` go with step 1,
   `HomeTab` and `RootTabView` with step 2).
4. **The detail hero** (build it only when the user says so). Until then
   the UIKit detail screen has no Play button, title or description; only
   Home's featured video can be played from a Play button. Reference is
   the Apple TV app's movie/show page on iPhone. Over the bottom of the
   artwork, attached to the scrolling page (it moves with the page, not
   with the artwork): the title (bold, centered, up to three lines) and the
   channel below it; a solid white Play capsule (play symbol and "Play";
   after watching, the play symbol with a short resume bar and the remaining
   time, e.g. "40m"; while preparing, a spinner and "Cancel") beside a solid
   dark gray + circle (checkmark when saved), both centered, not glass; two
   lines of description with MORE below it opening the full description in
   a sheet; the info line (duration · views · date, then badges such as HD
   and CC). Until the details load, the description and info line are
   placeholders; then everything appears in one animation (UIKit:
   `UIView.animate` with `.flushUpdates`; `VideoDetailModel` still uses
   SwiftUI's `withAnimation`, which does nothing on the UIKit screen).
   Behind the text a dark gray gradient for legibility: a long even area
   and a short, quick fade above about the Play button, not over the image
   itself, ending seamlessly in the page's black at the artwork's edge; a
   plain gradient, no blur or material. Build it as a content
   configuration in the page's first cell (`UIButton.Configuration`,
   observable model read in `updateProperties()`); commit 3557827
   (reverted because it came too early) is a starting point. The light
   blue test stage goes back to the dark stage with it.
5. **Later phases:** a mini player that is the same player as full screen
   (one `AVPlayer`: closing full screen keeps playing in the mini player,
   tapping it enlarges it); `MPNowPlayingSession` (AVKit's
   `externalMetadata` artist does not appear on the lock screen). Only
   when the user asks: iCloud sync via SwiftData, background refresh, App
   Intents, Spotlight, Handoff, widget.

Keep as is (already Apple's way): `AVPlayerViewController` full screen,
`AVAssetDownloadURLSession`, Settings.bundle, `ArtworkLoader`.

**Smaller items:**

- `UICollectionViewDataSourcePrefetching` for Home and Up Next artwork.
- The context menu's bubble shows the card's 272-point image at 320 points,
  slightly soft; request the larger (`.search`) artwork from the shared
  cache for it.
- `AVPlayer.isObservationEnabled` (iOS 26) could replace the KVO on
  `AVPlayerItem.status` in `NativePlayback`; it is a global switch set
  before the first player, and it touches the resume logic.
- The Xcode 27 SDK warns about `Sendable` in `VideoShareItem.swift`
  (LinkPresentation: add `@preconcurrency`; `nonisolated(unsafe)` is
  unnecessary there).

**Other open topics:**

- **Subtitles.** YouTube's HLS master already carries a WebVTT subtitle
  group, which AVPlayer shows; the user reports that only part of the
  tracks appear there. The resolver also parses the caption tracks (manual
  and auto-generated), unused so far. First check whether iOS 27's
  generated subtitles already cover the need; Apple's route otherwise is a
  subtitle media group via `AVAssetResourceLoader` (serving a modified
  master playlist and WebVTT from YouTube's timed text). The user wants
  this later; discuss the plan before building.
- Optional: sync watch progress with `NSUbiquitousKeyValueStore`.
- Known App Store blockers, the user's call: Innertube stream access
  (guideline 5.2.3 / YouTube terms) and "Apple" in the app name and texts
  (5.2.5).
- `KNOWN_ISSUES.md`: the interactive-dismissal backdrop issue is accepted.
  Do not retry fixes without a new, discriminating idea. One such idea
  exists now: every earlier attempt ran with the app linked against the
  iOS 26.5 SDK, and since 2026-09-26 it is linked against iOS 27, which can
  change AVKit's behavior. A plain recheck on device answers whether the
  issue remains; after that, the next step would be a brand-new minimal
  Xcode project and a Feedback Assistant report.
