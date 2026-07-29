#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_ANDROID_DIR="${YOUTUBE_RESOLVER_PROJECT_DIR:-$PROJECT_ROOT/extensions/youtube/android}"
OUTPUT_AAR="${YOUTUBE_RESOLVER_OUTPUT_AAR:-$PROJECT_ROOT/android/app/libs/lightly-youtube-resolver.aar}"
PREBUILT_AAR="${YOUTUBE_RESOLVER_AAR:-}"
GRADLEW="${YOUTUBE_RESOLVER_GRADLEW:-$PROJECT_ROOT/extensions/telegram/android/gradlew}"
REQUIRE_OBFUSCATED_YOUTUBE="${REQUIRE_OBFUSCATED_YOUTUBE:-1}"

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
      :resolver:testDebugUnitTest :resolver:assembleRelease
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

TEMP_CLASSES_JAR="$(mktemp)"
trap 'rm -f "$TEMP_CLASSES_JAR"' EXIT
unzip -p "$OUTPUT_AAR" classes.jar > "$TEMP_CLASSES_JAR"
CLASS_LIST="$(jar tf "$TEMP_CLASSES_JAR")"
grep -q '^lightly/youtube/resolver/YouTubeResolverBridge.class$' <<<"$CLASS_LIST" || {
  echo "YouTubeResolverBridge missing from AAR" >&2
  exit 1
}
BRIDGE_API="$(javap -classpath "$TEMP_CLASSES_JAR" -public lightly.youtube.resolver.YouTubeResolverBridge)"
grep -q 'public static final int apiVersion();' <<<"$BRIDGE_API" || {
  echo "YouTubeResolverBridge.apiVersion() missing from AAR" >&2
  exit 1
}
grep -q 'public static final java.lang.String resolve(android.content.Context, java.lang.String, java.lang.String);' <<<"$BRIDGE_API" || {
  echo "YouTubeResolverBridge.resolve(...) missing from AAR" >&2
  exit 1
}
if [[ "$REQUIRE_OBFUSCATED_YOUTUBE" == "1" ]]; then
  EXPOSED_INTERNAL_CLASSES="$(
    grep '^lightly/youtube/resolver/.*\.class$' <<<"$CLASS_LIST" |
      grep -v '^lightly/youtube/resolver/YouTubeResolverBridge.class$' || true
  )"
  if [[ -n "$EXPOSED_INTERNAL_CLASSES" ]]; then
    echo "YouTube resolver AAR still exposes implementation classes:" >&2
    printf '%s\n' "$EXPOSED_INTERNAL_CLASSES" >&2
    exit 1
  fi
fi

echo "YouTube resolver AAR: $OUTPUT_AAR"
sha256sum "$OUTPUT_AAR"
