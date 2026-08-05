# v1.0.11 Release Summary

This document covers the features and fixes merged after `v1.0.10`. The highlights are a new
music player and a round of YouTube resolution, floating video playback, and release supply-chain
improvements.

## User-Facing Changes

### Music player

Lightly now ships a music player covering both online and local playback:

- Manually configured music API base URL, with input normalization and explicit authentication
  errors.
- Online search, grouped browsing by artist/album, and multiple playback modes.
- Playback integrates with the system notification so it can be controlled from the lock screen
  or background, with resume support after returning to the app.
- Online tracks can be downloaded into the local library with normalized "Artist - Title"
  filenames; duplicate titles from different sources are disambiguated.
- Downloads, refreshes, and merges of duplicate remote-id copies preserve artwork, lyrics, and
  artist/album metadata.
- Local music supports natural sorting, batch deletion, resume prompts, and a unified playback
  queue.

### Floating video gestures

- Double-tap the left region to rewind 5 seconds; double-tap the right region to skip forward
  5 seconds.
- Drag horizontally to preview the target timestamp; the seek only happens on release, so the
  target stays predictable instead of overshooting or undershooting.
- Long-press the surface for 3x speed; releasing restores the previous rate.
- Double-tap the center to enter mini mode. Mini mode keeps only a close button instead of
  squeezing the progress bar and controls together; double-tap again to restore the full
  controls.
- Videos longer than one hour now display the hour component correctly.

## YouTube Resolution Fixes

The companion `yt-resolver` repository (`v0.0.4`) fixes several reliability issues:

- **Long videos resolved to only a fraction of their length**: GoogleVideo often returns ranged
  segment candidates for long content. The resolver previously treated an intermediate segment URL
  as the full result, so playback stopped around the half-hour mark. Ranged captures are now
  normalized into candidates that cover the full duration, and results without duration metadata
  are rejected instead of returned early.
- **Twenty-second budget timeouts**: already-visited watch pages reuse a cached page result, and
  the polling loop survives in-page navigation instead of losing the entire budget to one
  navigation reset.
- **Failures after repeated resolutions**: the Google Sorry challenge is only evaluated during
  top-level watch navigation; embedded challenge or risk-control resources no longer fail an
  otherwise healthy resolution.
- **Bounded, safe diagnostics**: duration and candidate-count logging is bounded and never emits
  cookies or fully signed media URLs.

## Release Supply Chain

This release requires the new `yt-resolver` AAR. The Lightly Release workflow continues to pin
the AAR through the `YOUTUBE_RESOLVER_AAR_URL` and `YOUTUBE_RESOLVER_AAR_SHA256` Actions
variables and verifies the hash before building:

- Before tagging `v1.0.11`, point both variables at the `yt-resolver.aar` from the `v0.0.4`
  resolver Release and its hash from `SHA256SUMS`.
- Do not reuse the `v1.0.10` AAR/hash, or the long-video fix will not reach the release build.
- Unchanged companions (Telegram / WebRTC / EasyTier) continue to reuse the published
  `plugins.json`.

## Verification

- Floating video gestures, hour-precision duration display, and mini mode are covered by widget
  and gesture-math tests.
- The resolver side covers ranged-capture normalization, watch-page cache reuse, scoped Sorry
  detection, and navigation-resilient polling.
- Release CI continues to verify the AAR hash, companion ABI/signature checks, and the final APK
  build.

Related documents:

- [GitHub Release and Plugin Delivery (CN)](github-release-delivery.md)
- [Optional Plugin Release Guide](optional-plugin-release.md)

---
