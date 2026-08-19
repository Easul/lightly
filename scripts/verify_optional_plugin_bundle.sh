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

read_certificate_digest() {
  local apk="$1"
  local output digest

  if ! output="$($APKSIGNER verify --print-certs "$apk" 2>&1)"; then
    echo "apksigner failed for $apk:" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  digest="$(
    printf '%s\n' "$output" |
      grep -Ei 'certificate.*sha-256|sha-256.*certificate' |
      grep -Eio '([[:xdigit:]]{2}:){31}[[:xdigit:]]{2}|[[:xdigit:]]{64}' |
      head -n 1 |
      tr -d ':' |
      tr '[:upper:]' '[:lower:]' || true
  )"
  if [[ -z "$digest" ]]; then
    echo "Could not parse signing certificate for $apk; apksigner output:" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$digest"
}

LIGHTLY_CERT="$(read_certificate_digest "$LIGHTLY_APK")"

for feature in telegram webrtc easytier life_runtime; do
  abis=(arm64-v8a armeabi-v7a)
  [[ "$feature" == "life_runtime" ]] && abis=(arm64-v8a)
  for abi in "${abis[@]}"; do
    apk="$PLUGIN_OUTPUT_DIR/${feature}-${abi}-release.apk"
    [[ -f "$apk" ]] || { echo "Missing plugin APK: $apk" >&2; exit 1; }
    cert="$(read_certificate_digest "$apk")"
    [[ "$cert" == "$LIGHTLY_CERT" ]] || {
      echo "Plugin certificate mismatch: $feature/$abi" >&2
      exit 1
    }
  done
done

echo "Verified all optional plugins match $(basename "$LIGHTLY_APK"): $LIGHTLY_CERT"
