#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CACHE_DIR="${LIFE_RUNTIME_GIT_CACHE:-$ROOT/extensions/life-runtime/.deps/git}"
OUTPUT_DIR="${LIFE_RUNTIME_GIT_DIR:-$ROOT/extensions/life-runtime/runtime/git}"
BASE_URL="https://packages.termux.dev/apt/termux-main"
STAGING="$CACHE_DIR/staging"
PREFIX="$STAGING/data/data/com.termux/files/usr"

PACKAGES=(
  "git|pool/main/g/git/git_2.55.0_aarch64.deb|21b16fa06837e5bf94ad257da532c40eb049c120d21f6cb60a6411c0bcee7197"
  "libcurl|pool/main/libc/libcurl/libcurl_8.21.0_aarch64.deb|ad644c7e16183d40eaf0f55df339021a69b25cc9b390e9634251e681be1ddcb8"
  "libexpat|pool/main/libe/libexpat/libexpat_2.8.3_aarch64.deb|86dac6db293a44dc2689d4a28fdba96e38fccd378a9c9ef17b4e840b4cf4d81c"
  "libiconv|pool/main/libi/libiconv/libiconv_1.18-1_aarch64.deb|b19e6f348034bb48d2a5590b5cb242769f682c476717374d134d004cc663dc84"
  "openssl|pool/main/o/openssl/openssl_1:3.6.3_aarch64.deb|86760e9ce736f463236f2c15b1eb3a3fdcfc5778d0fd7077a917448dcc90f3aa"
  "pcre2|pool/main/p/pcre2/pcre2_10.47_aarch64.deb|51f915d22de639bfca6ec029ae613987bbe3bc73626eede13319fd2e95f50b63"
  "zlib|pool/main/z/zlib/zlib_1.3.2_aarch64.deb|75e7d0af17fcc3b40004309fdc00a1ddb9ae08346dce5e269902c34ac3966ac9"
  "libnghttp2|pool/main/libn/libnghttp2/libnghttp2_1.70.0_aarch64.deb|ab2e0a3408fe4934ffdf774bd5049a265db2e6db62dcb651baecbecfb81e3f0b"
  "libnghttp3|pool/main/libn/libnghttp3/libnghttp3_1.18.0_aarch64.deb|0be2ee96def3608afaf24eb0b4b55f3484a37c95ea21bb1d6d85c7d543467603"
  "libngtcp2|pool/main/libn/libngtcp2/libngtcp2_1.25.0_aarch64.deb|f471bad7f4329b6b0b4aedf124e0a23a35f6ac99bfbae73304136f8bfd570fc3"
  "libssh2|pool/main/libs/libssh2/libssh2_1.11.1-2_aarch64.deb|1add4e0a926b848814e7e2f1817ea28b123c54cabd5bbc4e5cfd65291cbad84e"
  "ca-certificates|pool/main/c/ca-certificates/ca-certificates_1:2026.07.16_all.deb|93dc49a8009012c29510081b8f07f30c57af9b10b1dae4f541231d8ee785b37a"
)

mkdir -p "$CACHE_DIR/packages"
rm -rf "$STAGING" "$OUTPUT_DIR"
mkdir -p "$STAGING" "$OUTPUT_DIR/native/arm64-v8a" "$OUTPUT_DIR/assets/git"

for record in "${PACKAGES[@]}"; do
  IFS='|' read -r name relative checksum <<<"$record"
  package="$CACHE_DIR/packages/${name}.deb"
  if [[ ! -f "$package" ]] || [[ "$(sha256sum "$package" | cut -d' ' -f1)" != "$checksum" ]]; then
    curl --fail --location --retry 3 "$BASE_URL/$relative" --output "$package"
  fi
  echo "$checksum  $package" | sha256sum --check --status
  dpkg-deb --extract "$package" "$STAGING"
done

cp "$PREFIX/bin/git" "$OUTPUT_DIR/native/arm64-v8a/libgit.so"
cp "$PREFIX/libexec/git-core/git-remote-http" \
  "$OUTPUT_DIR/native/arm64-v8a/libgit_remote_http.so"

map_file="$OUTPUT_DIR/assets/git/native-libs.map"
: >"$map_file"
declare -A copied=()
while IFS= read -r library; do
  name="$(basename "$library")"
  real="$(readlink -f "$library")"
  real_name="$(basename "$real")"
  packed="$real_name"
  if [[ -z "${copied[$packed]:-}" ]]; then
    cp "$real" "$OUTPUT_DIR/native/arm64-v8a/$packed"
    copied[$packed]=1
  fi
  if [[ "$name" != "$packed" && ! -e "$OUTPUT_DIR/native/arm64-v8a/$name" ]]; then
    cp "$real" "$OUTPUT_DIR/native/arm64-v8a/$name"
  fi
  printf '%s=%s\n' "$name" "$packed" >>"$map_file"
done < <(find "$PREFIX/lib" -maxdepth 1 \( -type f -o -type l \) -name 'lib*.so*' | sort)

# Android's native packaging only accepts files ending in `.so`, while the
# Termux packages use SONAME filenames such as `libz.so.1`. Provide the exact
# loader names as regular files as well.
for alias in libz.so.1 libexpat.so.1 libssl.so libcrypto.so libz.so libexpat.so; do
  target="$(readlink -f "$PREFIX/lib/$alias")"
  if [[ -f "$target" ]]; then
    cp "$target" "$OUTPUT_DIR/native/arm64-v8a/$alias"
  fi
done

mkdir -p "$OUTPUT_DIR/assets/git/share/git-core" "$OUTPUT_DIR/assets/git/lib"
cp -R "$PREFIX/share/git-core/templates" "$OUTPUT_DIR/assets/git/share/git-core/"
cp "$OUTPUT_DIR/native/arm64-v8a"/lib*.so* "$OUTPUT_DIR/assets/git/lib/"
if [[ -f "$PREFIX/etc/tls/cert.pem" ]]; then
  mkdir -p "$OUTPUT_DIR/assets/git/etc/tls"
  cp "$PREFIX/etc/tls/cert.pem" "$OUTPUT_DIR/assets/git/etc/tls/cert.pem"
elif [[ -f "$PREFIX/etc/tls/certs/ca-certificates.crt" ]]; then
  mkdir -p "$OUTPUT_DIR/assets/git/etc/tls"
  cp "$PREFIX/etc/tls/certs/ca-certificates.crt" "$OUTPUT_DIR/assets/git/etc/tls/cert.pem"
else
  echo "Termux CA certificate bundle not found" >&2
  exit 1
fi

chmod 0755 "$OUTPUT_DIR/native/arm64-v8a"/*.so
echo "Prepared Git runtime in $OUTPUT_DIR"
