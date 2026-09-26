#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -o "$output/download-checks" \
  AppleVideos/Services/Downloads/DownloadPreparation.swift \
  AppleVideos/Services/Downloads/DownloadTaskIdentity.swift \
  Tests/Downloads/DownloadPreparationChecks.swift
"$output/download-checks"
