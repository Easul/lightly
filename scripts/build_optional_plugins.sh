#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-$PROJECT_ROOT/build/optional-plugins}"
if [[ -z "${PLUGIN_VERSION_CODE:-}" ]]; then
  MAIN_COMMIT_COUNT="$(
    git -C "$PROJECT_ROOT" rev-list --count main 2>/dev/null ||
      git -C "$PROJECT_ROOT" rev-list --count origin/main 2>/dev/null ||
      git -C "$PROJECT_ROOT" rev-list --count HEAD
  )"
  PLUGIN_VERSION_CODE="$((5000 + MAIN_COMMIT_COUNT))"
fi
PLUGIN_VERSION_NAME="${PLUGIN_VERSION_NAME:-$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || echo v1.0.0)+$(git -C "$PROJECT_ROOT" rev-parse --short=6 HEAD)}"
TELEGRAM_PLUGIN_API_VERSION="${TELEGRAM_PLUGIN_API_VERSION:-3}"
WEBRTC_PLUGIN_API_VERSION="${WEBRTC_PLUGIN_API_VERSION:-3}"
EASYTIER_PLUGIN_API_VERSION="${EASYTIER_PLUGIN_API_VERSION:-${PLUGIN_API_VERSION:-2}}"
MINIMUM_LIGHTLY_VERSION_CODE="${MINIMUM_LIGHTLY_VERSION_CODE:-$PLUGIN_VERSION_CODE}"
RELEASE_TAG="${PLUGIN_RELEASE_TAG:-plugins-${PLUGIN_VERSION_NAME//[^[:alnum:].+-]/-}}"
PLUGIN_RELEASE_REPOSITORY="${PLUGIN_RELEASE_REPOSITORY:-Easul/lightly-plugins}"
DEFER_LIGHTLY_CERT_VERIFY="${DEFER_LIGHTLY_CERT_VERIFY:-0}"
APKSIGNER="${APKSIGNER:-$(find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -1)}"
GRADLEW="${PLUGIN_GRADLEW:-$PROJECT_ROOT/extensions/telegram/android/gradlew}"
LIGHTLY_APK="${LIGHTLY_APK:-$PROJECT_ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk}"
PLUGIN_GRADLE_OFFLINE="${PLUGIN_GRADLE_OFFLINE:-1}"

GRADLE_NETWORK_ARGS=()
if [[ "$PLUGIN_GRADLE_OFFLINE" == "1" ]]; then
  GRADLE_NETWORK_ARGS+=(--offline)
fi

declare -A PLUGIN_DIRS=(
  [telegram]="$PROJECT_ROOT/extensions/telegram/android"
  [webrtc]="$PROJECT_ROOT/extensions/webrtc/android"
  [easytier]="$PROJECT_ROOT/extensions/easytier/android"
)
declare -A PLUGIN_PACKAGES=(
  [telegram]=lightly.tool.plugin.telegram
  [webrtc]=lightly.tool.plugin.webrtc
  [easytier]=lightly.tool.plugin.easytier
)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_command git
require_command sha256sum
require_command unzip
[[ -n "$APKSIGNER" && -x "$APKSIGNER" ]] || {
  echo "Android apksigner not found; set APKSIGNER explicitly" >&2
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

  # Build-tools versions differ in whether the SHA-256 digest is rendered as
  # colon-separated octets or as one contiguous hexadecimal string. Match the
  # digest value itself instead of depending on an English label or spacing.
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

if [[ "$GRADLEW" != */* ]]; then
  GRADLEW="$(command -v "$GRADLEW" || true)"
fi
[[ -x "$GRADLEW" ]] || { echo "Gradle executable not found: $GRADLEW" >&2; exit 1; }
LIGHTLY_CERT=""
if [[ -f "$LIGHTLY_APK" ]]; then
  LIGHTLY_CERT="$(read_certificate_digest "$LIGHTLY_APK")"
elif [[ "$DEFER_LIGHTLY_CERT_VERIFY" != "1" ]]; then
  echo "Lightly release APK not found: $LIGHTLY_APK. Build Lightly first or set DEFER_LIGHTLY_CERT_VERIFY=1 for the CI pre-host phase." >&2
  exit 1
fi

rm -rf "$PLUGIN_OUTPUT_DIR"
mkdir -p "$PLUGIN_OUTPUT_DIR/.work"

build_plugin() {
  local feature="$1"
  local abi="$2"
  local gradle_dir="${PLUGIN_DIRS[$feature]}"
  local apk_source="$gradle_dir/../build/app/outputs/apk/release/app-release.apk"
  local apk="$PLUGIN_OUTPUT_DIR/${feature}-${abi}-release.apk"

  TARGET_ABI="$abi" \
    PLUGIN_VERSION_CODE="$PLUGIN_VERSION_CODE" \
    PLUGIN_VERSION_NAME="$PLUGIN_VERSION_NAME" \
    "$GRADLEW" -p "$gradle_dir" "${GRADLE_NETWORK_ARGS[@]}" :app:assembleRelease >/dev/null
  cp "$apk_source" "$apk"

  local entries
  entries="$(unzip -Z1 "$apk")"
  if grep -Eiq '(^|/)(libflutter\.so|libapp\.so|libdartjni\.so|flutter_assets/|GeneratedPluginRegistrant\.class)' <<<"$entries"; then
    echo "Flutter/Dart runtime artifact found in $apk" >&2
    exit 1
  fi
  grep -q "^lib/$abi/" <<<"$entries" || {
    echo "Expected ABI $abi missing from $apk" >&2
    exit 1
  }
  while read -r path; do
    [[ -z "$path" || "$path" == "lib/$abi/"* ]] || {
      echo "Unexpected ABI slice $path in $apk" >&2
      exit 1
    }
  done < <(grep '^lib/[^/]\+/' <<<"$entries" || true)

  local cert size digest
  cert="$(read_certificate_digest "$apk")"
  size="$(stat -c '%s' "$apk")"
  digest="$(sha256sum "$apk" | awk '{print $1}')"
  printf '%s %s %s\n' "$size" "$digest" "$cert" > "$PLUGIN_OUTPUT_DIR/.work/${feature}-${abi}.metadata"
  echo "Built $feature $abi: $size bytes sha256=$digest cert=$cert"
}

for feature in telegram webrtc easytier; do
  for abi in arm64-v8a armeabi-v7a; do
    build_plugin "$feature" "$abi"
  done
done

EXPECTED_CERT=""
for feature in telegram webrtc easytier; do
  for abi in arm64-v8a armeabi-v7a; do
    cert="$(awk '{print $3}' "$PLUGIN_OUTPUT_DIR/.work/${feature}-${abi}.metadata")"
    if [[ -z "$EXPECTED_CERT" ]]; then EXPECTED_CERT="$cert"; fi
    [[ "$cert" == "$EXPECTED_CERT" ]] || {
      echo "Plugin certificates do not match: $feature/$abi" >&2
      exit 1
    }
    [[ -z "$LIGHTLY_CERT" || "$cert" == "$LIGHTLY_CERT" ]] || {
      echo "Plugin certificate does not match Lightly: $feature/$abi" >&2
      exit 1
    }
  done
done

artifact_json() {
  local feature="$1"
  local abi="$2"
  local metadata="$PLUGIN_OUTPUT_DIR/.work/${feature}-${abi}.metadata"
  local size digest
  size="$(awk '{print $1}' "$metadata")"
  digest="$(awk '{print $2}' "$metadata")"
  printf '"%s": {"url": "https://github.com/%s/releases/download/%s/%s-%s-release.apk", "sha256": "%s", "size": %s}' \
    "$abi" "$PLUGIN_RELEASE_REPOSITORY" "$RELEASE_TAG" "$feature" "$abi" "$digest" "$size"
}

cat > "$PLUGIN_OUTPUT_DIR/plugins.json" <<EOF
{
  "schemaVersion": 1,
  "plugins": {
    "telegram": {
      "packageName": "${PLUGIN_PACKAGES[telegram]}",
      "apiVersion": ${TELEGRAM_PLUGIN_API_VERSION},
      "versionCode": ${PLUGIN_VERSION_CODE},
      "versionName": "${PLUGIN_VERSION_NAME}",
      "minimumLightlyVersionCode": ${MINIMUM_LIGHTLY_VERSION_CODE},
      "artifacts": {$(artifact_json telegram arm64-v8a), $(artifact_json telegram armeabi-v7a)}
    },
    "webrtc_voice": {
      "packageName": "${PLUGIN_PACKAGES[webrtc]}",
      "apiVersion": ${WEBRTC_PLUGIN_API_VERSION},
      "versionCode": ${PLUGIN_VERSION_CODE},
      "versionName": "${PLUGIN_VERSION_NAME}",
      "minimumLightlyVersionCode": ${MINIMUM_LIGHTLY_VERSION_CODE},
      "artifacts": {$(artifact_json webrtc arm64-v8a), $(artifact_json webrtc armeabi-v7a)}
    },
    "easytier": {
      "packageName": "${PLUGIN_PACKAGES[easytier]}",
      "apiVersion": ${EASYTIER_PLUGIN_API_VERSION},
      "versionCode": ${PLUGIN_VERSION_CODE},
      "versionName": "${PLUGIN_VERSION_NAME}",
      "minimumLightlyVersionCode": ${MINIMUM_LIGHTLY_VERSION_CODE},
      "artifacts": {$(artifact_json easytier arm64-v8a), $(artifact_json easytier armeabi-v7a)}
    }
  }
}
EOF

rm -rf "$PLUGIN_OUTPUT_DIR/.work"
if [[ -n "$LIGHTLY_CERT" ]]; then
  echo "Verified plugin certificate matches $(basename "$LIGHTLY_APK"): $LIGHTLY_CERT"
else
  echo "Deferred Lightly certificate comparison; run scripts/verify_optional_plugin_bundle.sh after the final host build"
fi
echo "Wrote $PLUGIN_OUTPUT_DIR/plugins.json"
