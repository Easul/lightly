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
  "openssh|pool/main/o/openssh/openssh_10.5p1_aarch64.deb|110dcebd42eb4d147d7fdd132f8834e5cb5ff355ef9ed80385ad33698c984ebe"
  "openssh-sftp-server|pool/main/o/openssh-sftp-server/openssh-sftp-server_10.5p1_aarch64.deb|73711b9de70dddf74dc4061ebd301473fb6229d67ed5af67c7dd333142650b6b"
  "ripgrep|pool/main/r/ripgrep/ripgrep_15.2.0_aarch64.deb|38e28bc297000517b24702568a483eca7dc3323eb6bdccc9033f031776bdcc6c"
  "unzip|pool/main/u/unzip/unzip_6.0-10_aarch64.deb|9e0b3320ff446d9989c048047a305c679b66f30b6fb4b04225a54821af37345b"
  "zip|pool/main/z/zip/zip_3.0-7_aarch64.deb|0c121e7f633e439e3c46f6e661e7a3f488ef5ee446cdcff5aed4c9ddf25001bf"
  "krb5|pool/main/k/krb5/krb5_1.22.2_aarch64.deb|3c97dcc7437616bb4051297822915bd2ff9552e63a5fbee2520db3fc0c5b575d"
  "ldns|pool/main/l/ldns/ldns_1.8.4-1_aarch64.deb|8bd23534a13f8743458bf4c0add9bb30addee5f3f088c0b00c525a404e4097a4"
  "libandroid-support|pool/main/liba/libandroid-support/libandroid-support_29-1_aarch64.deb|f2f145d6135ad4843ac9670153be3e3944dc1e6f1736d46d2306c28f2b86f517"
  "libandroid-glob|pool/main/liba/libandroid-glob/libandroid-glob_0.6-3_aarch64.deb|2276ae8adedf0db76c2f4ffc94cc4cceb2f4f5d78e021b54e2e046d1233e7826"
  "libbz2|pool/main/libb/libbz2/libbz2_1.0.8-8_aarch64.deb|4335d7f060650b0aabef545d1334c2f9f280223d5962e13c24a00ec934b794ba"
  "resolv-conf|pool/main/r/resolv-conf/resolv-conf_1.3_aarch64.deb|ab541abac8e0c81709cd7ca4a02bcfa0d60ba1f4bfe7fd6dce4a694a4a9dfffa"
  "libresolv-wrapper|pool/main/libr/libresolv-wrapper/libresolv-wrapper_1.1.7-6_aarch64.deb|788de09ffcc307bdbaf541dbe06cf79e54d8a2390fef1223727ee33d9bdfee9e"
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

for tool in ssh rg unzip zip; do
  if [[ -f "$PREFIX/bin/$tool" ]]; then
    cp "$PREFIX/bin/$tool" "$OUTPUT_DIR/native/arm64-v8a/lib$tool.so"
  fi
done

mkdir -p "$OUTPUT_DIR/assets/git/share/git-core" "$OUTPUT_DIR/assets/git/lib"
cp -R "$PREFIX/share/git-core/templates" "$OUTPUT_DIR/assets/git/share/git-core/"
for library in \
  libcurl.so libcrypto.so.3 libssl.so.3 libz.so.1 libiconv.so libpcre2-8.so \
  libnghttp2.so libnghttp3.so libngtcp2.so libngtcp2_crypto_ossl.so libssh2.so \
  libandroid-support.so libandroid-glob.so libbz2.so.1.0 \
  libgssapi_krb5.so.2 libkrb5.so.3 libk5crypto.so.3 libcom_err.so.3 \
  libkrb5support.so.0 libresolv_wrapper.so libldns.so; do
  target="$PREFIX/lib/$library"
  if [[ -e "$target" ]]; then
    cp "$(readlink -f "$target")" "$OUTPUT_DIR/assets/git/lib/$library"
  fi
done

system_libraries=' libc.so libm.so libdl.so liblog.so '
for file in "$OUTPUT_DIR/native/arm64-v8a"/*.so "$OUTPUT_DIR/assets/git/lib"/*.so*; do
  while IFS= read -r library; do
    if [[ "$system_libraries" == *" $library "* ]]; then
      continue
    fi
    if [[ ! -f "$OUTPUT_DIR/assets/git/lib/$library" ]]; then
      echo "Missing runtime dependency $library required by $(basename "$file")" >&2
      exit 1
    fi
  done < <(readelf -d "$file" 2>/dev/null | sed -n '/NEEDED/s/.*\[\([^]]*\)\].*/\1/p')
done
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
