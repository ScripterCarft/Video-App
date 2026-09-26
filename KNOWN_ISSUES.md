# Known issues

## Player backdrop stops fading during an interactive swipe-down

**Status:** resolved on 2026-09-26 by building with the iOS 27 SDK. Every
attempt below ran with the app linked against the iOS 26.5 SDK (CI had no
newer Xcode) on iOS 27; the first build linked against iOS 27 dismissed
smoothly on device, with no app change to the player. Kept for reference:
if it ever returns, check which SDK the build used first.

### Symptom

While the native player (`AVPlayerViewController`) is dragged down, the video
shrinks and AVKit's black backdrop fades to reveal the video detail screen, as
intended. When the drag reverses (moving back up past a certain height) or
pauses, the backdrop jumps to fully black instead of following the finger.
After releasing, later drags in the same presentation do not fade at all.

It happens for any video and independently of the video; sometimes one
presentation works for a long time and the next one does not.

### What restores the fade

Any audio-output event that makes AVKit rebuild its playback chrome:

- changing the volume with the hardware buttons
- opening the AirPods case (the system AirPods card appears)

### Where it does not happen

Safari full-screen video and the Apple TV app on the same device.

### Ruled out

Each of these was tested on device, one change at a time, without effect:

- The black surface is AVKit's own backdrop. Coloring every app layer behind
  the player (detail background, root hosting view, window) showed none of
  them during the drag.
- SwiftUI work during the drag: the detail screen's tasks, artwork reloads,
  the launch-time Continue Watching refresh, watch-history writes and a status
  bar preference were all removed from the dismissal path.
- Presentation path: presenting from a `UIViewControllerRepresentable` host,
  from the window's top view controller, and from a separate `UIWindow` with an
  empty UIKit root. Reporting dismissal via
  `willEndFullScreenPresentationWithAnimationCoordinator` or via the host's
  `viewDidAppear`.
- Player configuration: `externalMetadata`, the audio session, the HLS
  resolution cap and `allowsExternalPlayback`.
- The stream: Apple's public HLS example stream behaves the same as YouTube.
- App settings: orientations, multiple-scene support, the global tint, the
  URL cache and the detail screen's navigation bar styling.
- A dismiss-and-re-present recovery after cancelled dismissals, based on a
  similar iOS 26 report (react-native-video#4864).
- **Apple's minimal recipe:** a button on an otherwise empty tab that runs
  only `AVPlayer(url:)`, `AVPlayerViewController`, `present(_:animated:)` and
  `play()` shows the same behavior in this app.

### Conclusion before the fix

The broken state lives inside AVKit's chrome and is reset by audio-route and
volume events. Because even the minimal recipe is affected inside this app but
not Safari or the TV app, the remaining difference is either in how those
system apps present their player or in something app-wide that was not
isolated. The next step, if revisited, is a brand-new Xcode project with only
the minimal recipe, and a Feedback Assistant report to Apple if that project
reproduces it.
