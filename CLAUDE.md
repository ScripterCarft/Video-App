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
- Streams are prefetched when a detail screen opens (and for the Home
  featured video); badges come from the resolved stream
  (`ResolvedPlaybackSource.technicalBadges`).
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
  HLS capped at 720p on every network; large images are requested with
  `allowsConstrainedNetworkAccess = false` and fall back quietly.
- `Video.publishedAt` stores the publish date; labels are formatted at
  display time. Search results get an approximate date from "N units ago".
- Watch progress: `LibraryStore` (`apple-videos.progress`, 200 entries),
  saved every 5 s and on pause, end, close and background; under 10 s or
  past 95 % is not kept (thresholds chosen by us, not Apple). Resume seeks
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
- Context menu (user's layout, `VideoLibraryActions` shared with the detail
  menu): Save and Share side by side on top; then Add to / Remove from
  Watchlist, Mark as Watched (in Watchlist), Remove from Recently Watched
  (trash, in History; the Library still says "History"). Nothing red.
- Detail screen: shows refreshed metadata, prefers the full description,
  MORE sits on the description's second line (TextKit line counting), does
  not bounce when content fits, white tint; its tasks keep finished state
  so nothing reloads when AVKit re-adds the screen.
- Home shelves: `scrollClipDisabled()` and `viewAligned` snapping.
- Removed on purpose: the empty Profile button and the Downloads placeholder
  (App Review rejects non-functional UI). "Up Next" stays at the user's
  request.
- Language mixing (UI English, YouTube texts in the device language) is left
  as is on the user's decision.

## Open work

1. **Subtitles (next).** The resolver already parses YouTube caption tracks
   (manual and auto-generated) but nothing uses them. AVPlayer only shows
   subtitles that are part of the HLS playlist. Apple's route is to add a
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
