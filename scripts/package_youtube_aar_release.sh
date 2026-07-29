#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${YOUTUBE_RESOLVER_VERSION:-v1.0.0}"
OUTPUT_DIR="${YOUTUBE_RELEASE_OUTPUT_DIR:-$PROJECT_ROOT/build/youtube-release}"
ASSET_NAME="lightly-youtube-resolver-${VERSION}.aar"
ASSET_PATH="$OUTPUT_DIR/$ASSET_NAME"

mkdir -p "$OUTPUT_DIR"
YOUTUBE_RESOLVER_OUTPUT_AAR="$ASSET_PATH" \
  REQUIRE_OBFUSCATED_YOUTUBE=1 \
  "$PROJECT_ROOT/scripts/build_youtube_aar.sh"

(
  cd "$OUTPUT_DIR"
  sha256sum "$ASSET_NAME" > SHA256SUMS
)

echo "YouTube resolver release assets:"
echo "  $ASSET_PATH"
echo "  $OUTPUT_DIR/SHA256SUMS"
