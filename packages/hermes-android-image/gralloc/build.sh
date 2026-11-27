#!/bin/bash
set -euo pipefail
sources=$1
headers=$2
ndk=$3
android=$4
output=$5
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$sources"/*.cpp "$sources"/*.h "$work/"
patch -d "$work" -p1 --fuzz=0 <"$(dirname "$0")/yv12.patch"
mkdir -p "$(dirname "$output")"
"$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android35-clang++" \
  -O2 -Wall -Werror -fPIC -shared -fno-exceptions -fno-rtti -nostdlib++ -DLOG_TAG='"gralloc"' \
  -I"$headers/libhardware" -I"$headers/libcutils" -I"$headers/libsystem" -I"$headers/liblog" \
  -Wl,-soname,gralloc.redroid.so -Wl,--no-undefined -Wl,-z,relro,-z,now -Wl,--build-id=sha1 \
  -L"$android/system/lib64" -o "$output" "$work"/*.cpp -llog -lcutils -lc++
chmod 0644 "$output"
