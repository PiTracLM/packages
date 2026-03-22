#!/bin/bash
# Build ncnn for Raspberry Pi 5 (native build)
# Usage: ./build-ncnn-native.sh [version] [distro]
#   version: ncnn release tag, e.g. 20250503 (default: 20250503)
#   distro: bookworm or trixie (default: trixie)

set -euo pipefail

NCNN_VERSION="${1:-20250503}"
DISTRO="${2:-trixie}"
BUILD_DIR="/var/tmp/ncnn-build-$$"
BASE_OUTPUT_DIR="${OUTPUT_DIR:-$HOME/pitrac-packages}"
DEBIAN_ARCH="arm64"
PACKAGE_VERSION="${NCNN_VERSION}-1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

case "$DISTRO" in
    bookworm|trixie)
        log_info "Building ncnn ${NCNN_VERSION} for Debian $DISTRO"
        ;;
    *)
        log_error "Unknown distribution: $DISTRO"
        exit 1
        ;;
esac

cleanup() {
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "$BUILD_DIR" ]]; then
        log_info "Build directory: $BUILD_DIR"
    fi
}
trap cleanup EXIT

log_info "Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log_info "Cloning ncnn ${NCNN_VERSION}..."
git clone --depth 1 --branch "${NCNN_VERSION}" \
    https://github.com/Tencent/ncnn.git
cd ncnn
git submodule update --init

PI5_CFLAGS="-march=armv8.2-a+fp16+dotprod -mtune=cortex-a76 -O3 -ftree-vectorize -ffast-math"

log_info "Configuring with Pi 5 optimizations..."
cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DNCNN_RUNTIME_CPU=ON \
    -DNCNN_VULKAN=OFF \
    -DNCNN_BUILD_TOOLS=OFF \
    -DNCNN_BUILD_EXAMPLES=OFF \
    -DNCNN_BUILD_BENCHMARK=OFF \
    -DNCNN_INSTALL_SDK=ON \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_CXX_FLAGS="$PI5_CFLAGS" \
    -DCMAKE_C_FLAGS="$PI5_CFLAGS"

NUM_JOBS=$(nproc)
log_info "Building with $NUM_JOBS jobs..."
cmake --build build -j"$NUM_JOBS" 2>&1 | tee "$BUILD_DIR/build.log"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log_error "Build failed. Log: $BUILD_DIR/build.log"
    exit 1
fi
log_success "Build complete"

# Package it up
log_info "Creating .deb package..."
PKG_DIR="$BUILD_DIR/libncnn-dev_${PACKAGE_VERSION}~${DISTRO}1_arm64"

mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu/pkgconfig"
mkdir -p "$PKG_DIR/usr/include"

# Install into staging area
DESTDIR="$PKG_DIR" cmake --install build

# ncnn installs to /usr/lib — move to multiarch path if needed
if [[ -d "$PKG_DIR/usr/lib/libncnn.a" ]] || [[ -f "$PKG_DIR/usr/lib/libncnn.a" ]]; then
    mv "$PKG_DIR/usr/lib/libncnn.a" "$PKG_DIR/usr/lib/aarch64-linux-gnu/"
fi

# Handle case where cmake installs to /usr/lib directly
if [[ -f "$PKG_DIR/usr/lib/libncnn.a" ]]; then
    mv "$PKG_DIR/usr/lib/libncnn.a" "$PKG_DIR/usr/lib/aarch64-linux-gnu/"
elif [[ -f "$PKG_DIR/usr/lib/aarch64-linux-gnu/libncnn.a" ]]; then
    : # already in the right place
else
    # find it wherever cmake put it
    LIBFILE=$(find "$PKG_DIR" -name "libncnn.a" -type f | head -1)
    if [[ -n "$LIBFILE" ]]; then
        cp "$LIBFILE" "$PKG_DIR/usr/lib/aarch64-linux-gnu/"
    else
        log_error "libncnn.a not found after install"
        exit 1
    fi
fi

# Move cmake config files if they exist
if [[ -d "$PKG_DIR/usr/lib/cmake" ]]; then
    mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu/cmake"
    mv "$PKG_DIR/usr/lib/cmake/ncnn" "$PKG_DIR/usr/lib/aarch64-linux-gnu/cmake/" 2>/dev/null || true
    rmdir "$PKG_DIR/usr/lib/cmake" 2>/dev/null || true
fi

# Create pkg-config file
cat > "$PKG_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/ncnn.pc" << EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib/aarch64-linux-gnu
includedir=\${prefix}/include

Name: ncnn
Description: High-performance neural network inference framework for ARM
Version: ${NCNN_VERSION}
Libs: -L\${libdir} -lncnn
Libs.private: -lpthread -lgomp
Cflags: -I\${includedir}
EOF

# Symlink for non-multiarch lookups
mkdir -p "$PKG_DIR/usr/lib/pkgconfig"
cd "$PKG_DIR/usr/lib/pkgconfig"
ln -sf ../aarch64-linux-gnu/pkgconfig/ncnn.pc ncnn.pc
cd "$BUILD_DIR"

cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: libncnn-dev
Version: ${PACKAGE_VERSION}~${DISTRO}1
Architecture: arm64
Maintainer: PiTrac Build <build@pitrac.local>
Section: libdevel
Priority: optional
Depends: libc6-dev, libstdc++-dev | libstdc++6
Description: ncnn inference framework for Raspberry Pi 5
 Lightweight neural network inference optimized for ARM Cortex-A76.
 Static library with hand-tuned NEON assembly kernels.
 Built with Pi 5 flags: ${PI5_CFLAGS}
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR"

OUTPUT_DIR="$BASE_OUTPUT_DIR/$DISTRO/$DEBIAN_ARCH"
mkdir -p "$OUTPUT_DIR"
mv "$PKG_DIR.deb" "$OUTPUT_DIR/"

log_success "==========================================="
log_success "ncnn ${NCNN_VERSION} built for $DISTRO"
log_success "==========================================="
echo ""
echo "Package: $OUTPUT_DIR/libncnn-dev_${PACKAGE_VERSION}~${DISTRO}1_arm64.deb"
echo ""
echo "Install: sudo dpkg -i $OUTPUT_DIR/libncnn-dev_${PACKAGE_VERSION}~${DISTRO}1_arm64.deb"
echo "Verify:  pkg-config --libs ncnn"
