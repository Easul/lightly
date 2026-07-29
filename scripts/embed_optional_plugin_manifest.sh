#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_MANIFEST="${PLUGIN_MANIFEST:-$PROJECT_ROOT/build/optional-plugins/plugins.json}"
TARGET_MANIFEST="${BUNDLED_PLUGIN_MANIFEST:-$PROJECT_ROOT/assets/optional_plugins/plugins.json}"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "$SOURCE_MANIFEST" ]] || { echo "Plugin manifest not found: $SOURCE_MANIFEST" >&2; exit 1; }

jq -e '
  . as $root |
  $root.schemaVersion == 1 and
  (["telegram", "webrtc_voice", "easytier"] | all(. as $id | $root.plugins[$id] != null)) and
  ($root.plugins | to_entries | all(
    .value as $plugin |
    $plugin.versionCode > 0 and
    $plugin.apiVersion > 0 and
    (["arm64-v8a", "armeabi-v7a"] | all(. as $abi |
      $plugin.artifacts[$abi].size > 0 and
      ($plugin.artifacts[$abi].sha256 | test("^[0-9a-f]{64}$")) and
      ($plugin.artifacts[$abi].url | startswith("https://github.com/"))
    ))
  ))
' "$SOURCE_MANIFEST" >/dev/null

mkdir -p "$(dirname "$TARGET_MANIFEST")"
cp "$SOURCE_MANIFEST" "$TARGET_MANIFEST"
echo "Embedded optional plugin manifest: $TARGET_MANIFEST"
