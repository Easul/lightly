#!/bin/bash
# Build script for multi-ABI APKs with versionCode based on commit count
# Local mode favors host stability over maximum build speed.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK_OUTPUT_DIR="$PROJECT_ROOT/build/app/outputs/flutter-apk"
SYMBOL_OUTPUT_DIR="$PROJECT_ROOT/build/app/outputs/symbols"
ANDROID_DIR="$PROJECT_ROOT/android"
GRADLEW="$ANDROID_DIR/gradlew"
GRADLE_WORKERS="${GRADLE_WORKERS:-2}"
ARM64_HEAP="${ARM64_HEAP:-6G}"
ARM32_HEAP="${ARM32_HEAP:-8G}"
METASPACE_SIZE="${METASPACE_SIZE:-2G}"
CODE_CACHE_SIZE="${CODE_CACHE_SIZE:-256m}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-5}"
APKANALYZER="${APKANALYZER:-$(command -v apkanalyzer 2>/dev/null || true)}"

print_memory_snapshot() {
  echo "🧠 Memory snapshot:"
  free -h || true
}

stop_gradle_daemons() {
  echo "🛑 Stopping Gradle daemons..."
  (
    cd "$ANDROID_DIR"
    ./gradlew --stop
  ) || true
}

cleanup_between_builds() {
  echo "🧹 Cleaning Flutter/Android intermediate build artifacts..."
  rm -rf \
    "$PROJECT_ROOT/.dart_tool/flutter_build" \
    "$PROJECT_ROOT/build/app/intermediates" \
    "$PROJECT_ROOT/build/app/kotlin" \
    "$ANDROID_DIR/.gradle"/kotlin \
    2>/dev/null || true
}

cooldown_host() {
  echo "⏳ Cooling down host for ${COOLDOWN_SECONDS}s..."
  sleep "$COOLDOWN_SECONDS"
  print_memory_snapshot
}

build_release_for_abi() {
  local abi="$1"
  local target_platform="$2"
  local heap_size="$3"

  GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=${GRADLE_WORKERS} -Dorg.gradle.jvmargs='-Xmx${heap_size} -XX:MaxMetaspaceSize=${METASPACE_SIZE} -XX:ReservedCodeCacheSize=${CODE_CACHE_SIZE} -XX:+HeapDumpOnOutOfMemoryError'"   _JAVA_OPTIONS="-Xmx${heap_size}"   TARGET_ABI="$abi"   BUILD_VERSION_LABEL="$VERSION_NAME"   BUILD_VERSION_CODE="$VERSION_CODE"   flutter build apk     --release     --target-platform "$target_platform"     --obfuscate     --split-debug-info="$SYMBOL_OUTPUT_DIR"
}

verify_apk_metadata() {
  local apk_path="$1"
  local apk_name
  apk_name="$(basename "$apk_path")"

  if [[ -n "$APKANALYZER" ]]; then
    echo "🔍 Verifying $apk_name manifest..."
    "$APKANALYZER" manifest print "$apk_path" | grep -E 'versionCode|versionName' || true
  else
    echo "⚠️  apkanalyzer not found; skipping manifest verification for $apk_name"
  fi

  echo "🔐 SHA256 ($apk_name):"
  sha256sum "$apk_path"
}

LATEST_TAG=${RELEASE_VERSION_TAG:-$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || git -C "$PROJECT_ROOT" tag --sort=-v:refname | head -1 2>/dev/null || echo "v1.0.0")}
echo "🏷️  Latest tag: $LATEST_TAG"

# Get commit hash for build label
COMMIT_HASH=$(git -C "$PROJECT_ROOT" rev-parse --short=6 HEAD 2>/dev/null || echo "unknown")

# Build version label: tag+commit
VERSION_NAME="${LATEST_TAG}+${COMMIT_HASH}"
echo "📋 Version: $VERSION_NAME"

COMMIT_COUNT=$(git -C "$PROJECT_ROOT" rev-list --count main 2>/dev/null || git -C "$PROJECT_ROOT" rev-list --count origin/main 2>/dev/null || git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo "1")
VERSION_CODE=$((5000 + COMMIT_COUNT))
echo "🔢 Version code: $VERSION_CODE (5000 + main commit count: $COMMIT_COUNT)"

echo "⚙️  Local conservative build mode enabled"
echo "   - Gradle daemon: disabled"
echo "   - Gradle parallel: disabled"
echo "   - Gradle workers max: $GRADLE_WORKERS"
echo "   - arm64 heap: $ARM64_HEAP"
echo "   - arm32 heap: $ARM32_HEAP"
print_memory_snapshot

# Clean previous outputs
echo "🧹 Cleaning previous APK outputs..."
rm -f "$APK_OUTPUT_DIR"/app-*.apk "$APK_OUTPUT_DIR"/*.sha1 2>/dev/null || true
cleanup_between_builds
stop_gradle_daemons
cooldown_host

# Build arm64-v8a (64-bit)
echo "🚀 Building arm64-v8a (64-bit)..."
build_release_for_abi arm64-v8a android-arm64 "$ARM64_HEAP"

# Save with ABI-specific name
mv "$APK_OUTPUT_DIR/app-release.apk" "$APK_OUTPUT_DIR/app-arm64-v8a-release.apk"
echo "✅ Saved: app-arm64-v8a-release.apk (version: $VERSION_NAME, code: $VERSION_CODE)"
verify_apk_metadata "$APK_OUTPUT_DIR/app-arm64-v8a-release.apk"

stop_gradle_daemons
cleanup_between_builds
cooldown_host

# Build armeabi-v7a (32-bit)
echo "🚀 Building armeabi-v7a (32-bit)..."
build_release_for_abi armeabi-v7a android-arm "$ARM32_HEAP"

# Save with ABI-specific name
mv "$APK_OUTPUT_DIR/app-release.apk" "$APK_OUTPUT_DIR/app-armeabi-v7a-release.apk"
echo "✅ Saved: app-armeabi-v7a-release.apk (version: $VERSION_NAME, code: $VERSION_CODE)"
verify_apk_metadata "$APK_OUTPUT_DIR/app-armeabi-v7a-release.apk"

stop_gradle_daemons

# Show results
echo ""
echo "📁 Build completed:"
ls -lh "$APK_OUTPUT_DIR"/app-*.apk
echo ""
echo "📝 Build Info:"
echo "  Version: $VERSION_NAME"
echo "  Version Code: $VERSION_CODE"
echo "  Tag: $LATEST_TAG"
echo "  Commit: $COMMIT_HASH"
