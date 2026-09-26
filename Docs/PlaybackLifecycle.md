# Playback lifecycle

## Decision (2026-09-26)

The mini player is removed, not hidden behind a setting. The last complete
experiment is preserved in Git at `5f40d6a` (layout approved; playback stall
unresolved). Its UI, observable transport state, transition resume logic and
temporary diagnostic menu/observers are removed from the app.

The device report showed the original player item still attached, a pause on
completed full-screen dismissal, and a separate waiting state with CoreMedia
error -16840. Removing the mini player is not proof that the stream error or
the reported gray PiP frame has been fixed.

## Ownership and transitions

- One NativePlayback owns one AVPlayer, item and AVPlayerViewController.
- Completing full-screen dismissal ends the session unless PiP is starting
  or active. Cancelling the gesture leaves the session intact.
- AVKit owns PiP, its controls, animations and system Now Playing integration.
- PiP restoration presents the same controller; no new source, seek or Play.
  The restoration flag prevents a PiP-stop callback from ending a presentation
  still in flight. A finished/replaced session cannot restore itself.
- Closing PiP without restoring the UI ends the session. Failed PiP startup
  also releases a session if no full-screen controller remains.
- Ending saves progress once, removes observations, cancels metadata work,
  pauses, detaches the controller and removes the current item.

## Lock screen and background

The product requests pause when the display is locked, including audio.
`AVPlayer.audiovisualBackgroundPlaybackPolicy = .pauses` expresses this to
AVFoundation. There is no lock-screen detector, timer, video-track toggling,
or automatic Play on unlock. An initial resume seek finishing in the background
must not start playback. Visible PiP remains managed by AVKit; device validation
must cover moving Home separately from locking the screen.

Keep the playback audio-session category and audio background capability:
these are also required for native PiP and AirPlay. Do not pause on
sceneWillResignActive: that also occurs during PiP startup and interruptions.

Pausing does not guarantee zero remaining network traffic: in-flight requests
and buffering may finish. An audible-only HLS presentation is not necessarily
an audio-only network transfer; the provider's renditions determine that.
There is no custom background audio extractor or second audio player here.
Do not claim Podcast-like bandwidth use without on-device network measurement.

## Device acceptance checks (not performed on Windows)

Use both an online YouTube video and a downloaded video to distinguish delivery
failures from presentation failures. Repeat with playback paused and running.

1. Full screen -> close: silence, progress retained, no mini player.
2. Full screen -> partial dismissal -> cancel: same frame/session, no restart.
3. Full screen -> lock for 30 seconds -> unlock: paused, Play resumes in place.
4. Full screen -> PiP -> Home: visible PiP works; controls remain responsive.
5. PiP -> lock for 30 seconds -> unlock: pause policy, image recovers, Play works.
6. PiP -> restore full screen -> PiP repeatedly: no new playback session,
   duplicate audio, lost position or permanently gray window.
7. Close PiP; start a different video while PiP is open: old playback ends.
8. Lock immediately during initial buffering/resume: no delayed app-issued Play.
9. AirPlay and an audio interruption: route/system controls remain functional.

If PiP remains gray, record whether audio advances, whether PiP Play works,
whether downloaded content behaves identically, and the iOS version. No
detach/reattach or delayed-seek workaround has been added without that evidence.

## Apple references

- [Background playback policies](https://developer.apple.com/documentation/avfoundation/avplayeraudiovisualbackgroundplaybackpolicy)
- [AVKit integration and avoiding premature background pauses](https://developer.apple.com/videos/play/wwdc2019/503/)
- [Native PiP ownership](https://developer.apple.com/videos/play/wwdc2021/10290/)
- [Audio session and required background capability](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
