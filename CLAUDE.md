# Apple Videos — working notes for Claude

Read this first in every new session. `README.md` describes behavior and
structure; this file holds the workflow, the principles behind decisions,
what is intentional, and what is still open. `KNOWN_ISSUES.md` holds the
accepted player-dismissal bug.

## Workflow

- **Branch:** all work happens on `cleanup`. Merge into `main` only when the
  user explicitly says "merge". Before merging, ask whether to squash
  (`cleanup` contains many experiment and revert commits from debugging) or
  keep the individual commits.
- **One change per commit**, with a message that says why. Experiments are
  labeled `EXPERIMENT` / `TEST (do not merge)` and reverted with `git revert`
  once they have answered their question.
- **Building:** the development machine is Windows. There is no Xcode, no
  Python and no local Swift compiler. GitHub Actions is the compiler: every
  push to any branch builds Debug (simulator) and Release (device) and
  uploads an unsigned IPA. Check results through the public API
  (`https://api.github.com/repos/ScripterCarft/Video-App/actions/runs?per_page=1&branch=cleanup`),
  polling about every 40 s; unauthenticated calls are limited to 60 per
  hour. On failure, the "Report compiler errors" step publishes errors as
  check-run annotations (`/check-runs/{job id}/annotations`). Never look for
  or read stored credentials. Job logs need admin rights; annotations are
  the only readable output, so CI steps report what matters as annotations.
- **SDK (2026-09-26):** until then CI ran on `macos-26`, whose newest Xcode
  (26.6) has the iOS 26.5 SDK: the app was linked against iOS 26 although
  its deployment target is iOS 27, and no iOS 27 API compiled. CI now runs
  on GitHub's `xcode-27` image (public preview, macOS 27, arm64; default
  Xcode 27.0, betas beside it unused), which has the iOS 27 SDK and
  simulators. Preview means possible queueing and instability. Unit tests
  (`AppleVideosTests`, Swift Testing, hosted in the app) run after the IPA,
  so a failing test never withholds a build; lines starting with PROBE
  report measured behavior as annotations.
- **Testing** happens only on the user's iPhone with the CI IPA (English
  device language). Say plainly that a change is untested on device, and
  give a short test list after each build.
- **Shell pitfalls here:** `sed` replacement strings drop backslashes, which
  broke Swift key paths (`\.status`, `\.displayScale`) and squashed
  multi-line inserts into one line. Use the Edit tool for anything with
  backslashes or several lines, and re-check the result.

## How the user wants to work

- Communicate in German. Be honest about uncertainty; never present a guess
  as a finding. When the cause is unknown, say so and propose a
  discriminating test instead of another speculative fix.
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

- **Innertube is the core concept.** `YouTubeService` (WEB client) provides
  search, details, the full description and `publishDate`. The playback
  resolver (VISIONOS client) provides HLS/progressive streams, formats and
  caption tracks. Both requests per detail screen are required: verified
  with real responses, WEB returns `UNPLAYABLE` without streamingData or
  captions, VISIONOS has no microformat or publish date. Innertube
  specifics stay inside these two files and `YouTubeWebConfiguration`.
- `YouTubeWebConfiguration` loads the API key, client version and visitor
  data once, is prewarmed at launch, shared by all Innertube requests and
  invalidated after rejected requests.
- The embedded YouTube player (`EmbeddedPlayerScreen`) is the fallback when
  no native stream plays.
- `NativePlayback` presents `AVPlayerViewController` modally from the
  window's top view controller. No SwiftUI host view, no custom gestures,
  no private AVKit subviews. `PlaybackStarter` + `playbackPresentation(_:)`
  are the only way screens start playback.
- Audio session category is set once at launch (`AppDelegate`). The app is
  portrait only; only `AVPlayerViewController` may rotate.
- Storage: SwiftData (`LibraryDatabase`): one `StoredVideo` per video
  (metadata once, list membership, download path) and one `WatchProgress`
  per started video, kept apart so queries over videos do not update while
  a video plays. Library screens use `@Query`; `LibraryStore` and
  `DownloadManager` do the writes and publish what other screens read.
  Earlier UserDefaults data and positions on video records are migrated
  once at launch.
- Detail loading (user's design): one task loads the details first; the
  description and info line are placeholders until then and everything
  appears in one animation; only afterwards is the stream prefetched (Play
  and stream badges). Refreshed metadata is stored when the screen leaves
  (`onDisappear`, not while the player covers it). The Home featured video
  still prefetches its stream.
- Navigation is value-based in every `NavigationStack`: `VideoLink` /
  `videoDestination(transition:)` for videos, route enums for library and
  Explore topics. Never mix view-destination `NavigationLink`s with
  value-based ones (that caused videos to pop right after opening).
- Artwork: YouTube lists `hq720`/`maxresdefault` exactly when they exist
  (verified), so `thumbnailURL` stores the best listed 16:9 image and
  `Video.artworkCandidates` requests the 1280 file only when listed. No
  size guessing. `ArtworkLoader` owns and shares downloads, uses the default
  cache policy (YouTube: `max-age=7200` + ETag), downsamples to the drawn
  width and keeps prepared images in an `NSCache`. Refresh keeps a stored
  thumbnail URL unless the details list a 1280 image and the stored one is
  smaller. The curated videos carry their known thumbnails.
- Low Data Mode (`NetworkConditions`): no 1280 artwork, no stream prefetch,
  HLS capped at 720p on every network, 60 s buffer; large images are
  requested with `allowsConstrainedNetworkAccess = false` and fall back
  quietly.
- Streaming Options (user's design) live in the Settings app
  (`Settings.bundle`, read by `StreamingSettings`): Use Mobile Data; Mobile
  Data High Quality / Automatic (default); Wi-Fi High Quality (default) /
  Data Saver. Automatic and Data Saver cap at 720p ("about 1 GB/hour";
  a hard 1 GB would force 480p for 60 fps videos, rejected). 60 s forward
  buffer on expensive networks, Data Saver and Low Data Mode; Wi-Fi High
  Quality keeps the automatic buffer (battery first). Use Mobile Data off
  blocks native and embedded playback on cellular with an alert.
- Measured on device (test build, reverted): AVPlayer plays only H.264 from
  YouTube's HLS; the VP9 variants (up to 4K) are not even recognized, so
  1080p60 is the maximum and codec rewriting is pointless. 720p60 averages
  2.2–2.6 Mbit/s, 1080p60 4.3. YouTube encodes HD of 60 fps uploads only at
  60 fps. The automatic buffer loaded 73–109 s ahead, a low-bitrate video
  entirely. AV1 exists only outside HLS (hardware decode from A17 Pro) and
  is not worth building now.
- `Video.publishedAt` stores the publish date; labels are formatted at
  display time. Search results get an approximate date from "N units ago".
- Watch progress: `LibraryStore` (in `StoredVideo`, 200 entries),
  saved every 5 s and on pause, end, close and background; under 10 s or
  past 95 % is not kept (thresholds chosen by us, not Apple). One rule
  (user's decision): a video counts as started after 10 s of actual
  playback (seeking does not count) or when it continues a saved
  position; only then is progress saved and the video added to History.
  Resume seeks
  on `readyToPlay` and starts playback only after the seek. The Play button
  shows the play symbol, a capsule `ProgressView` (8 pt) and the remaining
  time ("40m", "1m" under a minute).
- Library (user's decision): only Saved and History; playlists were
  removed (Watch Later migrated to the Watchlist, others to Saved). History
  stores the last 50 played videos with all shown metadata including the
  description (like Podcasts keeps episode data; only the video itself is
  not stored). The Watchlist = videos added by hand + started, unfinished
  History videos, newest activity first; Home shows it titled "Continue
  Watching". Finishing, Mark as Watched or Remove from Watchlist takes a
  video off (the latter two also clear its progress). Launch refreshes the
  first 8 Watchlist videos; Saved and History refresh when opened, once
  per video per launch, keeping stored data until fresh data replaces it.
- Context menu (user's layout, `VideoLibraryActions`): Download, Save/Unsave
  and Share side by side on top (`ControlGroup`); then Add to
  Watchlist (plus.circle) / Remove from Watchlist (minus.circle), Mark as
  Watched (rectangle.badge.checkmark, in Watchlist), Remove from Recently
  Watched (trash, in History, hidden while downloaded; the Library still
  says "History"). Only when downloaded: a separate, red Remove Download
  (trash), so there is never more than one trash item.
- Downloads (`Services/Downloads`, user's design, personal use; App Store
  guideline 5.2.3 forbids them): `DownloadManager` uses background
  `AVAssetDownloadURLSession`s (Wi-Fi only / with mobile data), pins the
  best H.264 variant with `AVAssetVariantQualifier(variant:)`, resolves a
  fresh link first, keeps only complete packages and plays them offline.
  Download Options in the Settings app: Use Mobile Data (default off, then
  downloads wait for Wi-Fi), Wi-Fi High Quality 1080p / Fast Downloads
  720p (default); mobile data always 720p. No HDR/Atmos line (YouTube HLS
  has neither). UI: detail toolbar button with `DownloadProgressRing` (tap
  stops), a downloaded video's button opens a system menu with "Download
  Again to Renew" / red "Remove Download"; context menu
  Download / Stop, hidden once downloaded; download symbol beside the
  duration; Library > Downloaded and History each with Remove All.
- Home (`HomeViewController`) and the detail screen
  (`VideoDetailViewController`) are UIKit screens in a
  `VideoNavigationController` (Home tab, inside the SwiftUI `TabView`);
  videos open through `VideoNavigator` with UIKit's zoom
  (`preferredTransition = .zoom`) from the card's artwork; open detail
  screens are kept in `@SceneStorage` and restored. Each screen's
  collection view is its view: compositional layout, diffable data source,
  observable data read in `updateProperties()` (UIKit tracks it, iOS 26+).
  Shelves (Continue Watching, Made for Tonight, Up Next) are one component:
  `VideoCells.shelfSection` (fixed sizes), `VideoCardConfiguration` (the
  UIKit card, a `UIContentConfiguration`), `VideoCells.headerConfiguration`
  (title only; section subtitles removed at the user's request) and
  `VideoContextMenus` (removals applied in
  `willEndContextMenuInteraction`; preview: the thumbnail alone in a padded
  bubble, UIKit preview controller, so the menu sits below; the card's
  artwork is the targeted highlight/dismissal preview). Featured and
  Spotlight on Home are still SwiftUI in cells. Search, Library and Explore
  are SwiftUI on purpose until Phase 3; they show the detail controller in a
  thin SwiftUI shell (`VideoDetailView`) with their own toolbar and zoom.
- Never SwiftUI in fixed-size UIKit cells and no estimated sizes on these
  screens (proved on device): SwiftUI content in a cell gives way to the
  bars and home indicator wherever the cell lies, which squeezed cards and
  slid titles over them; with estimated sizes the layout recursed in
  `_updateVisibleCellsNow` until an assertion crashed the app (iOS 27).
  Sizes are computed once from the text styles and invalidated on text
  size changes.
- Detail scrolling (user's design, like the TV app): the artwork is the
  collection view's background view, on the light blue TEST stage for now;
  a clear spacer (stage height minus the top inset; automatic insets, so the
  bar's scroll edge effect appears only after scrolling) and Up Next on a
  black page whose section background reaches two screen heights below the
  shelf. Scrolling down moves the artwork up at half speed; overshoot at
  the top scales it from its top edge (one transform per scroll frame).
  At the top a downward drag does not scroll (`DetailCollectionView`), so
  the zoom's swipe dismisses the screen. Download is a plain bar button
  item whose image is the progress ring; Share presents the share sheet
  from the bottom.
- Library lists (Saved, Downloaded, History) are a plain `List` so
  removals from a card's context menu animate; with ScrollView +
  LazyVStack neighbors jumped under the returning menu preview. Rejected:
  delaying the change 0.4 s (timing hack, reverted).
- Renew/Remove on the detail screen and Remove All (Downloaded, History)
  are system `Menu`s with a section header as the explanation (rejected:
  custom gray popover, confirmation dialogs). History Remove All keeps
  downloaded videos.
- Download investigation (test builds, reverted): the direct system
  download gets HTTP 401 from YouTube for many videos, immediately, while
  the same requests from the app succeed. Ruled out: headers, cookies,
  IP/IPv4-vs-IPv6 and HTTP version (webhook.site capture, same for app,
  AVPlayer and download service), subtitles, VP9 in the playlist. A local
  pass-through proxy in the app (the app fetches every playlist and
  segment) downloads reliably. Cause unknown; `DownloadURLProviding` is
  the place to add that route.
- Detail screen: white bar tint and light status bar (whether the SwiftUI
  tab view passes the status bar style on is untested), keeps the system
  scroll edge effect (user: needed for legibility); its loading keeps
  finished state so nothing reloads when AVKit covers the screen; refreshed
  metadata is stored when the screen leaves.
- Keep screens that take part in the zoom transition cheap to draw: the
  zoom redraws the live screen every frame. Proved on device: blurred,
  masked hero copies, text shadows, a material button and TextKit
  measuring made closing slow and left the app unresponsive (taps even
  hit the old Play button). The hero is the 16:9 thumbnail centered on
  system gray (dark on detail). No blurs, masks, shadows or materials on
  these screens without measuring.
- Home title: `toolbarTitleDisplayMode(.inlineLarge)` (compared on device).
- Removed on purpose: the empty Profile button (App Review rejects
  non-functional UI). "Up Next" stays at the user's
  request.
- Language mixing (UI English, YouTube texts in the device language) is left
  as is on the user's decision.

## Open work

0. **The rebuild (current, user-approved plan).** Goal: the app feels like
   one system, built the way Apple builds the TV and Podcasts apps; big
   rebuilds are fine. User's decision (2026-09-26): rebuild from the ground
   up in modern UIKit, screen by screen, with iOS 26/27 features checked at
   every step: real view controllers in UIKit navigation controllers, one
   UIKit card, one context menu. Done so far (see Intentional design): Home
   and the detail screen as UIKit screens, the shared shelf and card, the
   detail scrolling.

   **Next, the detail hero (write it down, build it only when the user
   says so):** reference is the Apple TV app's movie/show page on iPhone.
   Over the bottom of the artwork, attached to the scrolling page (it
   moves with the page, not with the artwork), in the same positions as
   the former SwiftUI hero: the title (bold, centered, up to three lines)
   and the channel below it; a solid white Play capsule (play symbol and
   "Play"; after watching, the play symbol with a short resume bar and the
   remaining time, e.g. "40m"; while preparing, a spinner and "Cancel")
   beside a solid dark gray + circle (checkmark when saved), both centered,
   not glass; two lines of description with MORE below it opening the full
   description in a sheet; the info line (duration · views · date, then
   badges such as HD and CC). Until the details load, the description and
   info line are placeholders; then everything appears in one animation.
   Behind the text a dark gray gradient for legibility: a long even area
   and a short, quick, unobtrusive fade above about the Play button, not
   over the image itself, ending seamlessly in the page's black at the
   artwork's edge; a plain gradient, no blur or material (the zoom redraws
   the screen every frame). Build it in UIKit as a content configuration in
   the page's first cell (`UIButton.Configuration`, observable model read
   in `updateProperties()`); commit 3557827 (reverted because it came too
   early) is a starting point. The light blue test stage goes back to the
   dark stage with it.

   **Found in the review of 2026-09-26, for the next sessions** (explain to
   the user before building; the order is the user's call):
   - Home's Featured and Spotlight cards are still SwiftUI in cells with
     estimated sizes, the pattern that squeezed and crashed elsewhere.
     Rebuild both in UIKit: Featured as its own content configuration (with
     the Play button, `UIButton.Configuration`), Spotlight as a
     `UIListContentConfiguration` (symbol, title, text) on a rounded
     `UIBackgroundConfiguration`; sizes computed, not estimated.
   - The app shell is still the SwiftUI `TabView` around the Home tab's
     `VideoNavigationController`. Moving to `UITabBarController` with
     `UITab`/`UISearchTab` (iOS 18) makes the whole shell UIKit and brings
     Phase 4's features the UIKit way: tab bar minimize on scroll and the
     bottom accessory for the mini player (iOS 26), iOS 27's
     `prominentTabIdentifier` and `UINavigationItem.barMinimizeBehavior`
     where they fit. It also makes the light status bar on the detail
     screen reliable (the navigation controller's `childForStatusBarStyle`
     is only honoured if every parent passes it on; untested inside
     SwiftUI). Restoration would move from `@SceneStorage` to the scene's
     `stateRestorationActivity` (iOS 27: `UIScene.extendStateRestoration`).
   - Phase 3 in UIKit: Search, Library and Explore as collection views with
     the same card and menu; Library lists with
     `UICollectionLayoutListConfiguration` and its swipe actions. Afterwards
     remove the SwiftUI leftovers: `VideoCard`, `VideoArtwork`,
     `VideoHeroArtwork`, `SectionHeader`, `VideoLink`,
     `RestorableNavigationStack`, the `VideoDetailView` shell,
     `DownloadToolbarButton`, `DownloadProgressRing`, `PlayButtonContent`.
   - Checked against Apple's documentation (2026-09-26): iOS 27's
     observation tracking in the section provider only invalidates the
     *layout* (sizes, arrangement); which videos a shelf shows stays the
     diffable snapshot, applied in `updateProperties()`, which already
     tracks the library by itself (iOS 26). Use the section provider's
     tracking only where a section's layout depends on observable state.
     Text size and light/dark are no longer registered by hand: the
     section provider and `updateProperties()` track traits automatically.
   - The context menu's bubble shows the card's 272-point image at 320
     points, slightly soft; request the larger (`.search`) artwork from the
     shared cache for it.
   - The detail screen sets the navigation bar's tint to white in
     `viewWillAppear` and Home resets it; with a UIKit shell, prefer
     per-screen appearance over changing the shared bar.
   - Downloads sometimes fail (the known HTTP 401 route, see Download
     investigation); the user parked it.
   - Commit a51e717 alone does not compile (it uses `VideoCells.zoomSource`
     from c214758); relevant only if the merge keeps single commits.

   Earlier phases, for reference:
   1. Foundation (done): shared cell + menu (`VideoCells`,
      `VideoContextMenus`); slim `VideoRoute` (ID + section) with
      `VideoCatalog` and `RestorableNavigationStack` per tab; watch progress
      as its own model; library lists via `@Query`. `Video` (value type for
      network results and routes) and `StoredVideo` (persistence) stay two
      types on purpose.
   2. Detail screen (done; since rebuilt in UIKit, see above): Up Next
      shelf of related videos (WEB `next`, `lockupViewModel`; 4:3
      `hqdefault` cropped to 16:9); `VideoDetailModel` loads details, then
      Up Next, then the stream.
   3. Explore, Search and the Library's video lists on the same collection
      view. Search gets `Tab(role: .search)` but must stay a normal tab in
      the bar, not separated (research the iOS 27 option first); recent
      searches. Library: its entry screen stays the compact list with
      icons; the video lists as a collection view are a trial the user
      judges on device.
   4. Tab bar minimizes on scroll; a mini player (`tabViewBottomAccessory`)
      that is the same player as full screen (one `AVPlayer`: closing full
      screen keeps playing in the mini player, tapping it enlarges it);
      `inlineLarge` titles on every tab; `MPNowPlayingSession`.
   5. Later, only when the user asks: iCloud sync via SwiftData, background
      refresh, App Intents, Spotlight, Handoff, widget.
   Keep as is (already Apple's way): `AVPlayerViewController` full screen,
   `AVAssetDownloadURLSession`, Settings.bundle, `ArtworkLoader`.
1. **Subtitles.** YouTube's HLS master already carries a WebVTT
   subtitle group, which AVPlayer shows; the user reports that only part
   of the tracks appear there. The resolver also parses the caption tracks
   (manual and auto-generated), unused so far. Apple's route is to add a
   subtitle media group via `AVAssetResourceLoader` (serving a modified
   master playlist and WebVTT from YouTube's timed text). Discuss the plan
   with the user before building.
2. Decide squash vs. individual commits when merging `cleanup` into `main`.
3. Optional later: sync watch progress with `NSUbiquitousKeyValueStore`;
   show the author on the lock screen via `MPNowPlayingSession` (AVKit's
   `externalMetadata` artist does not appear there).
4. Known App Store blockers, the user's call: Innertube stream access
   (guideline 5.2.3 / YouTube terms) and "Apple" in the app name and texts
   (5.2.5).
5. `KNOWN_ISSUES.md`: the interactive-dismissal backdrop issue is accepted.
   Do not retry fixes without a new, discriminating idea; the next step
   would be a brand-new minimal Xcode project and a Feedback Assistant
   report.
