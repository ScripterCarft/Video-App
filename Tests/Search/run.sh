#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -D SEARCH_CHECKS -o "$output/search-checks" \
  AppleVideos/Services/Networking/NetworkRequestPolicy.swift \
  AppleVideos/Models/Video.swift \
  AppleVideos/Services/Search/SearchResults.swift \
  AppleVideos/Services/Details/VideoDetailModel.swift \
  AppleVideos/Services/YouTube/YouTubeService.swift \
  AppleVideos/Services/YouTube/YouTubeWebConfiguration.swift \
  AppleVideos/Support/String+Whitespace.swift \
  Tests/Search/SearchResultsChecks.swift \
  Tests/Search/DetailLoadingChecks.swift
"$output/search-checks"
