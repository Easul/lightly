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
trap 'rm -f "$TEMP_AAR"' EXIT

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
