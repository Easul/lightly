#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_ANDROID_DIR="${YOUTUBE_RESOLVER_PROJECT_DIR:-$PROJECT_ROOT/extensions/youtube/android}"
OUTPUT_AAR="${YOUTUBE_RESOLVER_OUTPUT_AAR:-$PROJECT_ROOT/android/app/libs/lightly-youtube-resolver.aar}"
PREBUILT_AAR="${YOUTUBE_RESOLVER_AAR:-}"
GRADLEW="${YOUTUBE_RESOLVER_GRADLEW:-$PROJECT_ROOT/extensions/telegram/android/gradlew}"

mkdir -p "$(dirname "$OUTPUT_AAR")"

if [[ -n "$PREBUILT_AAR" ]]; then
  if [[ ! -f "$PREBUILT_AAR" ]]; then
    echo "YouTube resolver AAR not found: $PREBUILT_AAR" >&2
    exit 1
  fi
  cp "$PREBUILT_AAR" "$OUTPUT_AAR"
elif [[ -f "$PRIVATE_ANDROID_DIR/settings.gradle.kts" ]]; then
  TARGET_ABI="${TARGET_ABI:-arm64-v8a}" \
    "$GRADLEW" -p "$PRIVATE_ANDROID_DIR" --offline \
      :resolver:testReleaseUnitTest :resolver:assembleRelease
  cp "$PRIVATE_ANDROID_DIR/resolver/build/outputs/aar/resolver-release.aar" "$OUTPUT_AAR"
elif [[ -f "$OUTPUT_AAR" ]]; then
  echo "Using existing private YouTube resolver AAR: $OUTPUT_AAR"
elif [[ "${REQUIRE_PRIVATE_YOUTUBE:-0}" == "1" ]]; then
  echo "Private YouTube resolver source/AAR is required but unavailable" >&2
  exit 1
else
  echo "Private YouTube resolver unavailable; building Lightly without it"
  exit 0
fi

echo "YouTube resolver AAR: $OUTPUT_AAR"
sha256sum "$OUTPUT_AAR"
