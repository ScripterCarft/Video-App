# Apple Videos

A native, personal video app for iOS 27, built with SwiftUI.

## Product direction

- Four native tabs: Home, Explore, Library, and Search
- Curated Home feed
- Public YouTube search through a replaceable provider
- YouTube playback through the official embedded player
- Native `AVPlayer` support for direct MP4/HLS sources
- Saved videos and personal playlists stored on device
- Native navigation, context menus, sharing, haptics, and zoom transitions

The YouTube provider is deliberately isolated from the UI. The initial search implementation uses YouTube's web client endpoint for this personal prototype and may change without notice. Playback does not extract YouTube media URLs.

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

