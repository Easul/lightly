#!/bin/bash
# Build script for multi-ABI APKs with versionCode based on commit count

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK_OUTPUT_DIR="$PROJECT_ROOT/build/app/outputs/flutter-apk"

# Get latest tag or fallback to default
LATEST_TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || git -C "$PROJECT_ROOT" tag --sort=-v:refname | head -1 2>/dev/null || echo "v1.0.0")
echo "🏷️  Latest tag: $LATEST_TAG"

# Get commit hash for build label
COMMIT_HASH=$(git -C "$PROJECT_ROOT" rev-parse --short=6 HEAD 2>/dev/null || echo "unknown")

# Build version label: tag+commit
VERSION_NAME="${LATEST_TAG}+${COMMIT_HASH}"
echo "📋 Version: $VERSION_NAME"

# Calculate version code from main branch commit count with offset
# Using offset 5000 to ensure versionCode is always high enough for Android updates
COMMIT_COUNT=$(git -C "$PROJECT_ROOT" rev-list --count main 2>/dev/null || git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo "1")
VERSION_CODE=$((5000 + COMMIT_COUNT))
echo "🔢 Version code: $VERSION_CODE (5000 + main:$COMMIT_COUNT)"

# Clean previous outputs
echo "🧹 Cleaning previous APK outputs..."
rm -f "$APK_OUTPUT_DIR"/app-*.apk "$APK_OUTPUT_DIR"/*.sha1 2>/dev/null || true
rm -rf "$PROJECT_ROOT/build/app/intermediates" 2>/dev/null || true

# Build arm64-v8a (64-bit)
echo "🚀 Building arm64-v8a (64-bit)..."
TARGET_ABI=arm64-v8a \
BUILD_VERSION_LABEL="$VERSION_NAME" \
flutter build apk \
  --release \
  --target-platform android-arm64 \
  --obfuscate \
  --split-debug-info="$PROJECT_ROOT/build/app/outputs/symbols"

# Save with ABI-specific name
mv "$APK_OUTPUT_DIR/app-release.apk" "$APK_OUTPUT_DIR/app-arm64-v8a-release.apk"
echo "✅ Saved: app-arm64-v8a-release.apk (version: $VERSION_NAME, code: $VERSION_CODE)"

# Build armeabi-v7a (32-bit)
echo "🚀 Building armeabi-v7a (32-bit)..."
GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx12G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError'" \
_JAVA_OPTIONS='-Xmx12G' \
TARGET_ABI=armeabi-v7a \
BUILD_VERSION_LABEL="$VERSION_NAME" \
flutter build apk \
  --release \
  --target-platform android-arm \
  --obfuscate \
  --split-debug-info="$PROJECT_ROOT/build/app/outputs/symbols"

# Save with ABI-specific name
mv "$APK_OUTPUT_DIR/app-release.apk" "$APK_OUTPUT_DIR/app-armeabi-v7a-release.apk"
echo "✅ Saved: app-armeabi-v7a-release.apk (version: $VERSION_NAME, code: $VERSION_CODE)"

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
