#!/usr/bin/env bash
# Builds llama.cpp (MIT) as static libraries for iOS devices and the iOS Simulator.
# Output: <dest>/include (headers + module.modulemap), <dest>/ios/libllama.a, <dest>/sim/libllama.a
# Usage: scripts/build-llama.sh [dest]   (env LLAMA_TAG to choose the llama.cpp release tag)
set -euo pipefail
TAG="${LLAMA_TAG:-b12626}"
DEST="${1:-Vendor/llama}"
if [ -f "$DEST/ios/libllama.a" ] && [ -f "$DEST/sim/libllama.a" ] && [ "$(cat "$DEST/version" 2>/dev/null)" = "$TAG" ]; then
  echo "llama.cpp $TAG already built in $DEST"; exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 4 --retry-delay 3 -o "$WORK/src.tar.gz" "https://github.com/ggml-org/llama.cpp/archive/refs/tags/$TAG.tar.gz"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -type d -name 'llama.cpp-*' | head -1)"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

build_slice() { # name sysroot metal
  local name="$1" sysroot="$2" metal="$3" out="$WORK/build-$1"
  cmake -S "$SRC" -B "$out" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF \
    -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_METAL="$metal" -DGGML_METAL_EMBED_LIBRARY="$metal" \
    -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=Apple > "$WORK/cmake-$name.log" 2>&1 || { tail -n 60 "$WORK/cmake-$name.log"; exit 1; }
  cmake --build "$out" --config Release --target llama -j "$JOBS" > "$WORK/build-$name.log" 2>&1 || { grep -E "error" -A3 "$WORK/build-$name.log" | head -n 80; exit 1; }
  mkdir -p "$DEST/$name"
  # shellcheck disable=SC2046
  libtool -static -o "$DEST/$name/libllama.a" $(find "$out" -name '*.a' | sort)
  echo "Built $name slice: $(du -h "$DEST/$name/libllama.a" | cut -f1) from: $(find "$out" -name '*.a' -exec basename {} \; | tr '\n' ' ')"
}

rm -rf "$DEST"
mkdir -p "$DEST/include"
build_slice ios iphoneos ON
build_slice sim iphonesimulator OFF
cp "$SRC/include/llama.h" "$DEST/include/"
cp "$SRC"/ggml/include/*.h "$DEST/include/"
cat > "$DEST/include/module.modulemap" <<'MAP'
module llama {
    header "llama.h"
    export *
}
MAP
echo "$TAG" > "$DEST/version"
echo "llama.cpp $TAG ready in $DEST"
