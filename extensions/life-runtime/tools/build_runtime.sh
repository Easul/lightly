#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MINDGIT_ROOT="${MINDGIT_ROOT:-$ROOT/../mindgit}"
LIFE_RECORD_ROOT="${LIFE_RECORD_ROOT:-$ROOT/../life-record}"
OUTPUT_DIR="${LIFE_RUNTIME_BIN_DIR:-$ROOT/extensions/life-runtime/runtime/bin}"

mkdir -p "$OUTPUT_DIR"

if [[ "${SKIP_MINDGIT:-0}" != "1" ]]; then
  [[ -f "$MINDGIT_ROOT/go.mod" ]] || { echo "MindGit repository not found: $MINDGIT_ROOT" >&2; exit 1; }
  CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
    go build -trimpath -ldflags="-s -w" -o "$OUTPUT_DIR/mindgit" "$MINDGIT_ROOT"
fi

if [[ "${SKIP_LIFE_RECORD:-0}" != "1" ]]; then
  [[ -f "$LIFE_RECORD_ROOT/go.mod" ]] || { echo "Life Record repository not found: $LIFE_RECORD_ROOT" >&2; exit 1; }
  [[ -n "${CC_ANDROID_ARM64:-}" ]] || {
    echo "CC_ANDROID_ARM64 is required for life-record's CGO SQLite build" >&2
    exit 1
  }
  CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$CC_ANDROID_ARM64" \
    go build -trimpath -ldflags="-s -w" \
    -o "$OUTPUT_DIR/liferecord" "$LIFE_RECORD_ROOT/cmd/liferecord"
fi

chmod 0755 "$OUTPUT_DIR"/*
echo "Prepared Android runtime binaries in $OUTPUT_DIR"
