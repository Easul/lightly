#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-$PROJECT_ROOT/build/optional-plugins}"
LIGHTLY_APK="${LIGHTLY_APK:-$PROJECT_ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk}"
APKSIGNER="${APKSIGNER:-$(find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -1)}"

[[ -n "$APKSIGNER" && -x "$APKSIGNER" ]] || {
  echo "Android apksigner not found; set APKSIGNER explicitly" >&2
  exit 1
}
[[ -f "$LIGHTLY_APK" ]] || { echo "Lightly APK not found: $LIGHTLY_APK" >&2; exit 1; }
[[ -f "$PLUGIN_OUTPUT_DIR/plugins.json" ]] || {
  echo "Plugin manifest not found: $PLUGIN_OUTPUT_DIR/plugins.json" >&2
  exit 1
}

LIGHTLY_CERT="$($APKSIGNER verify --print-certs "$LIGHTLY_APK" 2>/dev/null | awk -F': ' '/Signer #1 certificate SHA-256 digest/ {print $2; exit}')"
[[ -n "$LIGHTLY_CERT" ]] || { echo "Could not read Lightly certificate" >&2; exit 1; }

for feature in telegram webrtc easytier; do
  for abi in arm64-v8a armeabi-v7a; do
    apk="$PLUGIN_OUTPUT_DIR/${feature}-${abi}-release.apk"
    [[ -f "$apk" ]] || { echo "Missing plugin APK: $apk" >&2; exit 1; }
    cert="$($APKSIGNER verify --print-certs "$apk" 2>/dev/null | awk -F': ' '/Signer #1 certificate SHA-256 digest/ {print $2; exit}')"
    [[ "$cert" == "$LIGHTLY_CERT" ]] || {
      echo "Plugin certificate mismatch: $feature/$abi" >&2
      exit 1
    }
  done
done

echo "Verified all optional plugins match $(basename "$LIGHTLY_APK"): $LIGHTLY_CERT"
