#!/bin/bash

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build"
EASYTIER_FORK_URL="${EASYTIER_FORK_URL:-https://github.com/Easul/EasyTier.git}"
EASYTIER_BASE_COMMIT="${EASYTIER_BASE_COMMIT:-b20075e3dca788e968d758b247242e92970eadb2}"
EASYTIER_BRANCH_NAME="${EASYTIER_BRANCH_NAME:-lightly/android-jni-b20075e3}"
EASYTIER_REPO_DIR="${EASYTIER_REPO_DIR:-$BUILD_ROOT/EasyTier}"
LEGACY_REPO_DIR="$BUILD_ROOT/easytier-fork/EasyTier"

JNI_DIR_REL="easytier-contrib/easytier-android-jni"
JNI_DIR="$EASYTIER_REPO_DIR/$JNI_DIR_REL"
BUILD_SH="$JNI_DIR/build.sh"
BUILD_RS="$JNI_DIR/build.rs"
LIB_RS="$JNI_DIR/src/lib.rs"

ARM64_OUTPUT="$EASYTIER_REPO_DIR/target/aarch64-linux-android/release"
ARMV7_OUTPUT="$EASYTIER_REPO_DIR/target/armv7-linux-androideabi/release"

ARM64_JNI_DEST="$PROJECT_ROOT/android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so"
ARM64_FFI_DEST="$PROJECT_ROOT/android/app/src/main/jniLibs/arm64-v8a/libeasytier_ffi.so"
ARMV7_JNI_DEST="$PROJECT_ROOT/android/app/src/main/jniLibs/armeabi-v7a/libeasytier_android_jni.so"
ARMV7_FFI_DEST="$PROJECT_ROOT/android/app/src/main/jniLibs/armeabi-v7a/libeasytier_ffi.so"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    exit 1
  fi
}

expected_build_rs() {
  cat <<'EOF'
use std::path::PathBuf;

fn main() {
    println!("cargo:rustc-link-lib=dylib=easytier_ffi");

    let target = std::env::var("TARGET").unwrap_or_default();
    let profile = std::env::var("PROFILE").unwrap_or_else(|_| "release".to_string());
    let manifest_dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo_root = manifest_dir.parent().and_then(|p| p.parent()).unwrap();
    let lib_path = repo_root.join("target").join(target).join(profile);

    println!("cargo:rustc-link-search=native={}", lib_path.display());
    println!("cargo:rerun-if-changed=build.rs");
}
EOF
}

expected_build_sh() {
  cat <<'EOF'
#!/bin/bash

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

detect_build_jobs() {
    if [ -n "$EASYTIER_BUILD_JOBS" ]; then
        echo "$EASYTIER_BUILD_JOBS"
        return
    fi

    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi

    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
        return
    fi

    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
        return
    fi

    echo 1
}

BUILD_JOBS=$(detect_build_jobs)
if [ -z "$BUILD_JOBS" ] || [ "$BUILD_JOBS" -lt 1 ] 2>/dev/null; then
    BUILD_JOBS=1
fi

echo "EasyTier Android JNI Build Script"
echo "================================"

if ! command -v rustc &> /dev/null; then
    echo "Error: Rust not found"
    exit 1
fi

if ! cargo ndk --version &> /dev/null; then
    echo "Error: cargo-ndk not installed. Run: cargo install cargo-ndk"
    exit 1
fi

echo "cargo-ndk version: $(cargo ndk --version)"
echo "Build jobs: $BUILD_JOBS"

ANDROID_TARGETS=("arm64-v8a" "armeabi-v7a")

declare -A TARGET_MAP
TARGET_MAP["arm64-v8a"]="aarch64-linux-android"
TARGET_MAP["armeabi-v7a"]="armv7-linux-androideabi"

echo "Installing Android target architectures..."
for android_target in "${ANDROID_TARGETS[@]}"; do
    rust_target="${TARGET_MAP[$android_target]}"
    if ! rustup target list --installed | grep -q "$rust_target"; then
        echo "Installing target: $rust_target (for $android_target)"
        rustup target add "$rust_target"
    else
        echo "Target already installed: $rust_target (for $android_target)"
    fi
done

OUTPUT_DIR="./target/android"
mkdir -p "$OUTPUT_DIR"

build_for_target() {
    local android_target=$1
    echo "Building target: $android_target"

    echo "Building easytier-ffi for $android_target"
    (cd $REPO_ROOT/easytier-contrib/easytier-ffi && CARGO_BUILD_JOBS=$BUILD_JOBS cargo ndk -t $android_target build --release)

    CARGO_BUILD_JOBS=$BUILD_JOBS cargo ndk -t $android_target build --release

    rust_target="${TARGET_MAP[$android_target]}"
    mkdir -p "$OUTPUT_DIR/$android_target"
    cp "$REPO_ROOT/target/$rust_target/release/libeasytier_android_jni.so" "$OUTPUT_DIR/$android_target/"
    cp "$REPO_ROOT/target/$rust_target/release/libeasytier_ffi.so" "$OUTPUT_DIR/$android_target/"
    echo "Libraries copied to: $OUTPUT_DIR/$android_target/"
}

if [ -z "$ANDROID_NDK_ROOT" ] && [ -z "$ANDROID_NDK_HOME" ] && [ -z "$NDK_HOME" ]; then
    echo "Warning: Android NDK environment variables not set"
    echo "cargo-ndk will attempt to auto-detect NDK path"
else
    if [ -n "$ANDROID_NDK_ROOT" ]; then
        echo "Using Android NDK: $ANDROID_NDK_ROOT"
    elif [ -n "$ANDROID_NDK_HOME" ]; then
        echo "Using Android NDK: $ANDROID_NDK_HOME"
    elif [ -n "$NDK_HOME" ]; then
        echo "Using Android NDK: $NDK_HOME"
    fi
fi

echo "Building all target architectures..."
for target in "${ANDROID_TARGETS[@]}"; do
    build_for_target "$target"
done

echo "Build complete!"
echo "All library files generated at: $OUTPUT_DIR"
echo ""
echo "Directory structure:"
ls -la "$OUTPUT_DIR"/*/

echo ""
echo "Usage:"
echo "1. Copy .so files to your Android project's src/main/jniLibs/"
echo "2. Copy java/com/easytier/jni/EasyTierJNI.java to your Android project"
echo "3. Call EasyTierJNI class methods in your Android code"
EOF
}

ensure_repo_checkout() {
  mkdir -p "$BUILD_ROOT"

  if [ ! -d "$EASYTIER_REPO_DIR/.git" ] && [ -d "$LEGACY_REPO_DIR/.git" ]; then
    echo "♻️ Migrating legacy checkout to $EASYTIER_REPO_DIR"
    mv "$LEGACY_REPO_DIR" "$EASYTIER_REPO_DIR"
  fi

  if [ -d "$EASYTIER_REPO_DIR/.git" ]; then
    echo "📦 Reusing existing EasyTier checkout: $EASYTIER_REPO_DIR"
    git -C "$EASYTIER_REPO_DIR" remote set-url origin "$EASYTIER_FORK_URL"
    git -C "$EASYTIER_REPO_DIR" fetch origin --tags
  else
    echo "📥 Cloning fork into $EASYTIER_REPO_DIR"
    git clone "$EASYTIER_FORK_URL" "$EASYTIER_REPO_DIR"
  fi
}

lib_rs_has_link_attr() {
  python3 - "$LIB_RS" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding='utf-8')
sys.exit(0 if '#[link(name = "easytier_ffi", kind = "dylib")]' in text else 1)
PY
}

files_already_prepared() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  expected_build_rs > "$tmp_dir/build.rs"
  expected_build_sh > "$tmp_dir/build.sh"

  local ready=0
  if cmp -s "$BUILD_RS" "$tmp_dir/build.rs" \
    && cmp -s "$BUILD_SH" "$tmp_dir/build.sh" \
    && lib_rs_has_link_attr; then
    ready=1
  fi

  rm -rf "$tmp_dir"
  [ "$ready" -eq 1 ]
}

branch_already_prepared() {
  git -C "$EASYTIER_REPO_DIR" show-ref --verify --quiet "refs/heads/$EASYTIER_BRANCH_NAME" || return 1
  git -C "$EASYTIER_REPO_DIR" merge-base --is-ancestor "$EASYTIER_BASE_COMMIT" "$EASYTIER_BRANCH_NAME" || return 1
  git -C "$EASYTIER_REPO_DIR" checkout "$EASYTIER_BRANCH_NAME" >/dev/null 2>&1
  files_already_prepared
}

apply_overrides() {
  echo "🩹 Applying EasyTier JNI overrides"
  expected_build_rs > "$BUILD_RS"
  expected_build_sh > "$BUILD_SH"
  chmod +x "$BUILD_SH"

  python3 - "$LIB_RS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
attr = '#[link(name = "easytier_ffi", kind = "dylib")]\n'
needle = 'unsafe extern "C" {'

if attr.strip() not in text:
    if needle not in text:
        raise SystemExit('unsafe extern block not found in src/lib.rs')
    text = text.replace(needle, attr + needle, 1)

path.write_text(text, encoding='utf-8')
PY
}

prepare_branch() {
  if branch_already_prepared; then
    echo "♻️ Repo, branch, and override files are already prepared; reusing existing checkout"
    return
  fi

  echo "🧹 Preparing branch from base commit"
  git -C "$EASYTIER_REPO_DIR" checkout -B "$EASYTIER_BRANCH_NAME" "$EASYTIER_BASE_COMMIT"
  apply_overrides
}

build_libraries() {
  echo "🚀 Building EasyTier Android JNI libraries"
  (
    cd "$JNI_DIR"
    bash ./build.sh
  )
}

copy_built_libraries() {
  echo "📦 Copying built libraries into Flutter jniLibs"

  mkdir -p \
    "$(dirname "$ARM64_JNI_DEST")" \
    "$(dirname "$ARMV7_JNI_DEST")"

  cp "$ARM64_OUTPUT/libeasytier_android_jni.so" "$ARM64_JNI_DEST"
  cp "$ARM64_OUTPUT/libeasytier_ffi.so" "$ARM64_FFI_DEST"
  cp "$ARMV7_OUTPUT/libeasytier_android_jni.so" "$ARMV7_JNI_DEST"
  cp "$ARMV7_OUTPUT/libeasytier_ffi.so" "$ARMV7_FFI_DEST"
}

hash_and_compare() {
  echo "🔍 Comparing built outputs with vendored Flutter jniLibs"
  sha256sum \
    "$ARM64_OUTPUT/libeasytier_android_jni.so" \
    "$ARM64_OUTPUT/libeasytier_ffi.so" \
    "$ARMV7_OUTPUT/libeasytier_android_jni.so" \
    "$ARMV7_OUTPUT/libeasytier_ffi.so"

  cmp -s "$ARM64_OUTPUT/libeasytier_android_jni.so" "$ARM64_JNI_DEST" && echo "✅ arm64 jni: identical" || echo "⚠️ arm64 jni: different"
  cmp -s "$ARM64_OUTPUT/libeasytier_ffi.so" "$ARM64_FFI_DEST" && echo "✅ arm64 ffi: identical" || echo "⚠️ arm64 ffi: different"
  cmp -s "$ARMV7_OUTPUT/libeasytier_android_jni.so" "$ARMV7_JNI_DEST" && echo "✅ armv7 jni: identical" || echo "⚠️ armv7 jni: different"
  cmp -s "$ARMV7_OUTPUT/libeasytier_ffi.so" "$ARMV7_FFI_DEST" && echo "✅ armv7 ffi: identical" || echo "⚠️ armv7 ffi: different"
}

echo "🔧 EasyTier Android build"
echo "📁 Project root: $PROJECT_ROOT"
echo "📦 EasyTier checkout: $EASYTIER_REPO_DIR"
echo "🌐 Fork URL: $EASYTIER_FORK_URL"
echo "🔖 Base commit: $EASYTIER_BASE_COMMIT"
echo "🌿 Working branch: $EASYTIER_BRANCH_NAME"

require_command git
require_command bash
require_command python3
require_command cargo
require_command rustup

if ! cargo ndk --version >/dev/null 2>&1; then
  echo "❌ cargo-ndk is not installed. Run: cargo install cargo-ndk"
  exit 1
fi

ensure_repo_checkout
prepare_branch
build_libraries
copy_built_libraries
hash_and_compare

echo ""
echo "📁 EasyTier checkout: $EASYTIER_REPO_DIR"
echo "🌿 Active branch: $(git -C "$EASYTIER_REPO_DIR" branch --show-current)"
echo "🔖 HEAD: $(git -C "$EASYTIER_REPO_DIR" rev-parse HEAD)"
