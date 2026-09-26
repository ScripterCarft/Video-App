#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -D SEARCH_CHECKS -o "$output/search-checks" \
  AppleVideos/Models/Video.swift \
  AppleVideos/Services/Search/SearchResults.swift \
  AppleVideos/Services/YouTubeService.swift \
  AppleVideos/Services/YouTubeWebConfiguration.swift \
  AppleVideos/Support/String+Whitespace.swift \
  Tests/Search/SearchResultsChecks.swift
"$output/search-checks"
