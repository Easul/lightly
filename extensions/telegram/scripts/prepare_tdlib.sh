#!/usr/bin/env bash
set -euo pipefail

TDLIB_VERSION="1.6.0"
TDLIB_ARCHIVE_SHA256="4aa3cbb7c3a1231104e2b61c77d56c7c719bd048d5b52ffa3195f9ec0d2e1724"
TDLIB_ARM64_SHA256="0d86ea855a79711d5bd9e053206a7b58e157d17f2f1aa3f2ea69747203fac2d7"
TDLIB_ARM32_SHA256="1e67f845dc1cf60a4f19277ded35a7dfe8bdc23521f4e9a23e92b61aa6d24b14"
TDLIB_ARCHIVE_URL="${TDLIB_ARCHIVE_URL:-https://pub.dev/api/archives/tdlib-${TDLIB_VERSION}.tar.gz}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPENDENCY_DIR="$PLUGIN_DIR/.deps/tdlib-$TDLIB_VERSION"
JNI_DIR="$DEPENDENCY_DIR/jniLibs"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

verify_file() {
  local path="$1"
  local expected="$2"
  [[ -f "$path" ]] && [[ "$(file_sha256 "$path")" == "$expected" ]]
}

require_command sha256sum
require_command awk
require_command tar

if verify_file "$JNI_DIR/arm64-v8a/libtdjson.so" "$TDLIB_ARM64_SHA256" &&
  verify_file "$JNI_DIR/armeabi-v7a/libtdjson.so" "$TDLIB_ARM32_SHA256"; then
  echo "TDLib $TDLIB_VERSION Android binaries are already prepared at $JNI_DIR"
  exit 0
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lightly-tdlib.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
ARCHIVE_PATH="$TEMP_DIR/tdlib-$TDLIB_VERSION.tar.gz"

if [[ -n "${TDLIB_ARCHIVE_PATH:-}" ]]; then
  if [[ ! -f "$TDLIB_ARCHIVE_PATH" ]]; then
    echo "TDLIB_ARCHIVE_PATH does not exist: $TDLIB_ARCHIVE_PATH" >&2
    exit 1
  fi
  cp "$TDLIB_ARCHIVE_PATH" "$ARCHIVE_PATH"
else
  require_command curl
  curl --fail --location --retry 3 --output "$ARCHIVE_PATH" "$TDLIB_ARCHIVE_URL"
fi

ACTUAL_ARCHIVE_SHA256="$(file_sha256 "$ARCHIVE_PATH")"
if [[ "$ACTUAL_ARCHIVE_SHA256" != "$TDLIB_ARCHIVE_SHA256" ]]; then
  echo "TDLib archive checksum mismatch: expected $TDLIB_ARCHIVE_SHA256, got $ACTUAL_ARCHIVE_SHA256" >&2
  exit 1
fi

EXTRACT_DIR="$TEMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR" \
  LICENSE \
  android/src/main/jniLibs/arm64-v8a/libtdjson.so \
  android/src/main/jniLibs/armeabi-v7a/libtdjson.so

EXTRACTED_JNI_DIR="$EXTRACT_DIR/android/src/main/jniLibs"
if ! verify_file "$EXTRACTED_JNI_DIR/arm64-v8a/libtdjson.so" "$TDLIB_ARM64_SHA256" ||
  ! verify_file "$EXTRACTED_JNI_DIR/armeabi-v7a/libtdjson.so" "$TDLIB_ARM32_SHA256"; then
  echo "Extracted TDLib Android library checksum mismatch" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEPENDENCY_DIR")"
rm -rf "$DEPENDENCY_DIR"
mkdir -p "$DEPENDENCY_DIR"
mv "$EXTRACTED_JNI_DIR" "$JNI_DIR"
cp "$EXTRACT_DIR/LICENSE" "$DEPENDENCY_DIR/LICENSE"

echo "Prepared TDLib $TDLIB_VERSION Android binaries at $JNI_DIR"
