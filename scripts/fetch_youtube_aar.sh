#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="${YOUTUBE_RESOLVER_AAR_URL:-}"
EXPECTED_SHA256="${YOUTUBE_RESOLVER_AAR_SHA256:-}"
OUTPUT_AAR="${YOUTUBE_RESOLVER_OUTPUT_AAR:-$PROJECT_ROOT/android/app/libs/lightly-youtube-resolver.aar}"
TOKEN="${YOUTUBE_RESOLVER_GITHUB_TOKEN:-}"

[[ "$URL" == https://* ]] || { echo "YOUTUBE_RESOLVER_AAR_URL must be HTTPS" >&2; exit 1; }
[[ "$EXPECTED_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "YOUTUBE_RESOLVER_AAR_SHA256 must contain 64 hexadecimal characters" >&2
  exit 1
}

mkdir -p "$(dirname "$OUTPUT_AAR")"
TEMP_AAR="$OUTPUT_AAR.download"
PRIVATE_DOWNLOAD_DIR=""
cleanup() {
  rm -f "$TEMP_AAR"
  if [[ -n "$PRIVATE_DOWNLOAD_DIR" ]]; then
    rm -rf "$PRIVATE_DOWNLOAD_DIR"
  fi
}
trap cleanup EXIT
rm -f "$TEMP_AAR"

if [[ -n "$TOKEN" && "$URL" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/?#]+)$ ]]; then
  command -v gh >/dev/null 2>&1 || {
    echo "gh is required to download a private GitHub Release asset" >&2
    exit 1
  }
  OWNER="${BASH_REMATCH[1]}"
  REPOSITORY="${BASH_REMATCH[2]}"
  RELEASE_TAG="${BASH_REMATCH[3]}"
  ASSET_NAME="${BASH_REMATCH[4]}"
  PRIVATE_DOWNLOAD_DIR="$(mktemp -d)"
  GH_TOKEN="$TOKEN" gh release download "$RELEASE_TAG" \
    --repo "$OWNER/$REPOSITORY" \
    --pattern "$ASSET_NAME" \
    --dir "$PRIVATE_DOWNLOAD_DIR"
  mv "$PRIVATE_DOWNLOAD_DIR/$ASSET_NAME" "$TEMP_AAR"
else
  CURL_ARGS=(
    --fail
    --location
    --proto '=https'
    --proto-redir '=https'
    --connect-timeout 20
    --max-time 300
    --retry 3
    --retry-all-errors
    --retry-delay 2
    --output "$TEMP_AAR"
  )
  if [[ -n "$TOKEN" ]]; then
    CURL_ARGS+=(--header "Authorization: Bearer $TOKEN")
  fi
  curl "${CURL_ARGS[@]}" "$URL"
fi

ACTUAL_SHA256="$(sha256sum "$TEMP_AAR" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256,,}" != "${EXPECTED_SHA256,,}" ]]; then
  echo "YouTube resolver AAR SHA-256 mismatch" >&2
  echo "Expected: ${EXPECTED_SHA256,,}" >&2
  echo "Actual:   ${ACTUAL_SHA256,,}" >&2
  exit 1
fi

mv "$TEMP_AAR" "$OUTPUT_AAR"
echo "Fetched YouTube resolver AAR: $OUTPUT_AAR"
echo "SHA-256: $ACTUAL_SHA256"
