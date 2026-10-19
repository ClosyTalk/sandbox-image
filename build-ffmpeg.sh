#!/bin/sh
set -eu
. /build/downloads.env
case "$1" in
  amd64) vpx_target=x86_64-linux-gcc ;;
  arm64) vpx_target=arm64-linux-gcc ;;
  *) echo "Unsupported architecture: $1" >&2; exit 1 ;;
esac
fetch() {
  curl --fail --show-error --silent --location --retry 3 \
    --connect-timeout 30 --max-time 300 "$1" -o "$2"
  printf '%s  %s\n' "$3" "$2" | sha256sum --check
}
cd /build
fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" ffmpeg.tar.xz "$FFMPEG_SOURCE_SHA256"
fetch https://ffmpeg.org/ffmpeg-devel.asc ffmpeg-devel.asc "$FFMPEG_SIGNING_KEY_SHA256"
curl --fail --show-error --silent --location --retry 3 \
  --connect-timeout 30 --max-time 300 \
  "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz.asc" -o ffmpeg.tar.xz.asc
export GNUPGHOME=/build/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --import ffmpeg-devel.asc
gpg --batch --status-fd 1 --verify ffmpeg.tar.xz.asc ffmpeg.tar.xz > signature.status
grep -q "^\[GNUPG:\] VALIDSIG ${FFMPEG_SIGNING_KEY_FINGERPRINT} " signature.status
fetch "https://codeload.github.com/webmproject/libvpx/tar.gz/${LIBVPX_COMMIT}" libvpx.tar.gz "$LIBVPX_SOURCE_SHA256"
mkdir libvpx
tar -xzf libvpx.tar.gz --strip-components=1 -C libvpx
tar -xJf ffmpeg.tar.xz

cd /build/libvpx
grep -F "v${LIBVPX_VERSION}" CHANGELOG
./configure --target="$vpx_target" --prefix=/opt/ffmpeg-deps \
  --enable-static --disable-shared --enable-pic \
  --disable-vp9 --disable-vp8-decoder --disable-examples --disable-tools \
  --disable-docs --disable-unit-tests
make -j "$(nproc)"
make install

cd "/build/ffmpeg-${FFMPEG_VERSION}"
export PKG_CONFIG_PATH=/opt/ffmpeg-deps/lib/pkgconfig
# agent-browser v0.39.0 native/recording.rs: PNG on stdin, or PPM with
# --cursor; pad to even dimensions, convert to yuv420p, encode VP8 into WebM.
# scale/format support the automatic pixel-format conversion. No audio,
# network, hardware acceleration, GPL/nonfree codecs, ffprobe or VP9.
./configure --prefix=/usr/local \
  --disable-everything --disable-autodetect --disable-network \
  --disable-doc --disable-debug --disable-shared --enable-static \
  --disable-gpl --disable-nonfree --disable-version3 \
  --disable-ffprobe --disable-avdevice --disable-swresample \
  --enable-ffmpeg --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale \
  --enable-zlib --enable-libvpx --enable-decoder=png,ppm --enable-parser=png,pnm \
  --enable-encoder=libvpx_vp8 --enable-demuxer=image2pipe \
  --enable-muxer=webm --enable-protocol=file,pipe \
  --enable-filter=pad,scale,format \
  --pkg-config-flags=--static --extra-ldflags=-static
make -j "$(nproc)"
install -m 755 ffmpeg /usr/local/bin/ffmpeg
# Fail if an accidental shared dependency enters either architecture's binary.
readelf -d /usr/local/bin/ffmpeg > /build/ffmpeg-dynamic.txt
if grep -q '(NEEDED)' /build/ffmpeg-dynamic.txt; then
  cat /build/ffmpeg-dynamic.txt >&2
  exit 1
fi
mkdir -p /usr/local/share/licenses/ffmpeg /usr/local/share/licenses/libvpx \
  /usr/local/share/sandbox/ffmpeg-build
cp COPYING.LGPLv2.1 LICENSE.md /usr/local/share/licenses/ffmpeg/
cp /build/libvpx/LICENSE /build/libvpx/PATENTS /usr/local/share/licenses/libvpx/
# Preserve configuration and source identities for auditing the static binary.
cp /build/downloads.env /build/build-ffmpeg.sh /build/signature.status \
  /usr/local/share/sandbox/ffmpeg-build/
cp config.h config_components.h /usr/local/share/sandbox/ffmpeg-build/
# Supply corresponding sources alongside the LGPL executable for rebuilding.
cp /build/ffmpeg.tar.xz /build/libvpx.tar.gz /usr/local/share/sandbox/ffmpeg-build/
ffmpeg -version
