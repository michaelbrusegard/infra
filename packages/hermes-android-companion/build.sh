#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: build.sh PLATFORM_ZIP BUILD_TOOLS_ZIP SIGNING_KEY_PK8 SIGNING_CERT_X509 VERSION_CODE VERSION_NAME OUTPUT_APK" >&2
  exit 2
fi

platform_zip=$1
build_tools_zip=$2
signing_key_pk8=$3
signing_cert_x509=$4
version_code=$5
version_name=$6
output_apk=$7
source_root=$(cd "$(dirname "$0")" && pwd)
build_root=$(mktemp -d)
trap 'rm -rf "$build_root"' EXIT

unzip -q "$platform_zip" -d "$build_root/platform"
unzip -q "$build_tools_zip" -d "$build_root/build-tools"
android_jar=$(find "$build_root/platform" -type f -name android.jar -print -quit)
build_tools=$(find "$build_root/build-tools" -type f -name aapt2 -printf '%h\n' -quit)

if [ -z "$android_jar" ] || [ -z "$build_tools" ]; then
  echo "unable to locate the pinned Android platform or build tools" >&2
  exit 1
fi

mkdir -p "$build_root/classes" "$build_root/dex"
"$build_tools/aapt2" compile \
  --dir "$source_root/res" \
  -o "$build_root/resources.zip"
"$build_tools/aapt2" link \
  -I "$android_jar" \
  --manifest "$source_root/AndroidManifest.xml" \
  --min-sdk-version 30 \
  --target-sdk-version 37 \
  --version-code "$version_code" \
  --version-name "$version_name" \
  -o "$build_root/resources.apk" \
  "$build_root/resources.zip"

mapfile -d '' java_sources < <(find "$source_root/src" -type f -name '*.java' -print0)
javac --release 11 \
  -classpath "$android_jar" \
  -d "$build_root/classes" \
  "${java_sources[@]}"

mapfile -d '' class_files < <(find "$build_root/classes" -type f -name '*.class' -print0)
"$build_tools/d8" \
  --lib "$android_jar" \
  --min-api 30 \
  --output "$build_root/dex" \
  "${class_files[@]}"

cp "$build_root/resources.apk" "$build_root/unsigned.apk"
(
  cd "$build_root/dex"
  zip -q -j "$build_root/unsigned.apk" classes.dex
)
mkdir -p "$(dirname "$output_apk")"
"$build_tools/apksigner" sign \
  --key "$signing_key_pk8" \
  --cert "$signing_cert_x509" \
  --out "$output_apk" \
  "$build_root/unsigned.apk"
"$build_tools/apksigner" verify --verbose --print-certs "$output_apk"
