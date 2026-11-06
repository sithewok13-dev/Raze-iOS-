#!/bin/bash
# Builds the static iOS (arm64) libraries Raze needs into $1:
# SDL2 (+ SDL2main), OpenAL Soft, ZMusic and libvpx.
set -ex
DEPS="$1"
: "${IOS_MIN:=15.0}"
: "${SDL_TAG:=release-2.32.8}"
: "${OPENAL_TAG:=1.24.3}"
: "${ZMUSIC_SHA:=d3b730795784bff3f97571446101c57c1c6ac9bc}"
: "${VPX_TAG:=v1.15.2}"
WORK="${RUNNER_TEMP:-/tmp}/ios-deps-src"
rm -rf "$WORK"; mkdir -p "$WORK" "$DEPS"
IOSFLAGS=(-G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
          -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" -DCMAKE_BUILD_TYPE=Release
          -DCMAKE_INSTALL_PREFIX="$DEPS" -DBUILD_SHARED_LIBS=OFF)

# --- SDL2
git clone -q --depth 1 -b "$SDL_TAG" https://github.com/libsdl-org/SDL.git "$WORK/SDL"
cmake -S "$WORK/SDL" -B "$WORK/SDL/build" "${IOSFLAGS[@]}" \
  -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_HIDAPI=OFF
cmake --build "$WORK/SDL/build"
cmake --install "$WORK/SDL/build"

# --- OpenAL Soft (CoreAudio backend)
git clone -q --depth 1 -b "$OPENAL_TAG" https://github.com/kcat/openal-soft.git "$WORK/openal"
cmake -S "$WORK/openal" -B "$WORK/openal/build" "${IOSFLAGS[@]}" \
  -DLIBTYPE=STATIC -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
  -DALSOFT_INSTALL_CONFIG=OFF -DALSOFT_INSTALL_HRTF_DATA=OFF -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF \
  -DALSOFT_BACKEND_COREAUDIO=ON -DALSOFT_REQUIRE_COREAUDIO=ON
cmake --build "$WORK/openal/build"
cmake --install "$WORK/openal/build"

# --- ZMusic (MIDI and tracker music; sndfile/mpg123 are loaded at run time, so absent on iOS)
git clone -q https://github.com/ZDoom/ZMusic.git "$WORK/zmusic"
git -C "$WORK/zmusic" checkout -q "$ZMUSIC_SHA"
# No FluidSynth (needs glib) and no CoreMIDI on iOS: MIDI uses ZMusic's other synths
python3 "$(dirname "$0")/zmusic_ios.py" "$WORK/zmusic"
# Homebrew's pkg-config would hand it Mac libraries (glib): hide them
PKG_CONFIG_LIBDIR=/nonexistent PKG_CONFIG_PATH= \
  cmake -S "$WORK/zmusic" -B "$WORK/zmusic/build" "${IOSFLAGS[@]}" \
  -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON
cmake --build "$WORK/zmusic/build"
cmake --install "$WORK/zmusic/build"

# --- libvpx (VP8 decoder for cutscene videos; its own configure, iOS = arm64-darwin-gcc)
git clone -q --depth 1 -b "$VPX_TAG" https://github.com/webmproject/libvpx.git "$WORK/libvpx"
(cd "$WORK/libvpx" && ./configure --target=arm64-darwin-gcc --prefix="$DEPS" \
  --extra-cflags="-miphoneos-version-min=$IOS_MIN" --extra-cxxflags="-miphoneos-version-min=$IOS_MIN" \
  --disable-examples --disable-tools --disable-docs --disable-unit-tests \
  --disable-vp8-encoder --disable-vp9-encoder --disable-shared --enable-static \
  && make -j"$(sysctl -n hw.ncpu)" && make install)

test -f "$DEPS/lib/libSDL2.a"
test -f "$DEPS/lib/libSDL2main.a"
test -f "$DEPS/lib/libopenal.a"
test -f "$DEPS/lib/libzmusic.a"
test -f "$DEPS/lib/libvpx.a"
ls -la "$DEPS/lib"
