#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -D STORAGE_CHECKS -o "$output/storage-checks" \
  AppleVideos/Services/Networking/NetworkRequestPolicy.swift \
  AppleVideos/Models/Video.swift \
  AppleVideos/Models/PlaybackProgress.swift \
  AppleVideos/Persistence/Models/*.swift \
  AppleVideos/Persistence/LibraryDatabase.swift \
  AppleVideos/Persistence/LibraryStorageStatus.swift \
  AppleVideos/Persistence/Migrations/*.swift \
  AppleVideos/Services/Library/LibraryStore.swift \
  AppleVideos/Services/YouTube/YouTubeService.swift \
  AppleVideos/Services/YouTube/YouTubeWebConfiguration.swift \
  AppleVideos/Support/String+Whitespace.swift \
  Tests/Persistence/StorageRegressionChecks.swift
"$output/storage-checks"
