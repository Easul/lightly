#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MINDGIT_ROOT="${MINDGIT_ROOT:-$ROOT/../mindgit}"
LIFE_RECORD_ROOT="${LIFE_RECORD_ROOT:-$ROOT/../life-record}"
OUTPUT_DIR="${LIFE_RUNTIME_BIN_DIR:-$ROOT/extensions/life-runtime/runtime/bin}"

mkdir -p "$OUTPUT_DIR"

android_compiler() {
  if [[ -n "${CC_ANDROID_ARM64:-}" ]]; then
    printf '%s\n' "$CC_ANDROID_ARM64"
    return
  fi

  local ndk compiler
  for ndk in \
    "${ANDROID_NDK_HOME:-}" \
    "${ANDROID_NDK_ROOT:-}" \
    "$HOME/software/android/sdk/ndk/28.2.13676358" \
    "$HOME/Android/Sdk/ndk/28.2.13676358"; do
    [[ -n "$ndk" ]] || continue
    compiler="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang"
    if [[ -x "$compiler" ]]; then
      printf '%s\n' "$compiler"
      return
    fi
  done
  return 1
}

if [[ "${SKIP_MINDGIT:-0}" != "1" ]]; then
  [[ -f "$MINDGIT_ROOT/go.mod" ]] || { echo "MindGit repository not found: $MINDGIT_ROOT" >&2; exit 1; }
  CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
    go -C "$MINDGIT_ROOT" build -trimpath -ldflags="-s -w" \
      -o "$OUTPUT_DIR/mindgit" .
fi

if [[ "${SKIP_LIFE_RECORD:-0}" != "1" ]]; then
  [[ -f "$LIFE_RECORD_ROOT/go.mod" ]] || { echo "Life Record repository not found: $LIFE_RECORD_ROOT" >&2; exit 1; }
  CC_ANDROID_ARM64="$(android_compiler)" || {
    echo "Android NDK arm64 compiler not found; set CC_ANDROID_ARM64 or ANDROID_NDK_HOME" >&2
    exit 1
  }
  CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$CC_ANDROID_ARM64" \
    go -C "$LIFE_RECORD_ROOT" build -trimpath -ldflags="-s -w" \
      -o "$OUTPUT_DIR/liferecord" ./cmd/liferecord
fi

chmod 0755 "$OUTPUT_DIR"/*
if [[ "${SKIP_GIT_RUNTIME:-0}" != "1" ]]; then
  "$(dirname "${BASH_SOURCE[0]}")/prepare_git_runtime.sh"
fi
echo "Prepared Android runtime binaries in $OUTPUT_DIR"
