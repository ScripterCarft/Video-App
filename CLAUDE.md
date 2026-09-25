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
  or read stored credentials.
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
- Storage: SwiftData (`StoredVideo`, `LibraryDatabase`), one record per
  video with its metadata once, list membership (saved, watched, added to
  the Watchlist), progress and download path; lists are queries, unused
  records are deleted. `LibraryStore`/`DownloadManager` publish lists read
  from it and reassign only changes (progress saves during playback must
  not re-render). Earlier UserDefaults data is migrated once at launch.
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
- Home is one `UICollectionView` (`HomeCollection`) with a compositional
  layout: featured, shelves as orthogonal sections
  (`continuousGroupLeadingBoundary`), Spotlight; Apple's intended design for
  App Store-style pages (WWDC19). Cells host the SwiftUI cards via
  `UIHostingConfiguration`; diffable data source; the collection view owns
  the context menus and applies removals in `willEndContextMenuInteraction`
  so cards leave after the menu closes. Other screens keep the SwiftUI card
  menu (`VideoCard.providesContextMenu`).
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
- Detail screen: shows refreshed metadata, prefers the full description
  (two lines, MORE below), does not bounce when content fits, white tint,
  keeps the system scroll edge effect (user: needed for legibility); its
  tasks keep finished state so nothing
  reloads when AVKit re-adds the screen.
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
   rebuilds are fine. Principle: every screen showing videos is a
   `UICollectionView` with a compositional layout, one shared cell
   (`VideoCells`) and one context menu (`VideoContextMenus`); SwiftUI stays
   for the shell (tabs, navigation, sheets) and for cell content via
   `UIHostingConfiguration`. Phases, one commit per step, tested on device:
   1. Foundation: shared cell + menu (done), a router per tab with slim
      typed routes (video ID, restorable path), views reading SwiftData
      (`@Query` where AVKit is not affected), one video model.
   2. Detail screen as a scrolling collection view: hero section, real
      shelves (related videos from Innertube `next`) instead of the "Up
      Next" placeholder, hero under the bar with `backgroundExtensionEffect`.
      Play and + stay solid, not glass (like the TV app).
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
   The detail screen is temporarily always scrollable (TEST commit
   ef911a8, revert once phase 2 makes it a scrolling collection view).
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
