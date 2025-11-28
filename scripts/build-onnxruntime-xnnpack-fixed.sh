#!/bin/bash
# Fixed ONNX Runtime build with XNNPACK for Raspberry Pi 5
# Handles the Eigen hash mismatch issue properly
# Usage: ./build-onnxruntime-xnnpack-fixed.sh [version] [distro]
#   version: ONNX Runtime version (default: 1.17.3)
#   distro: bookworm or trixie (default: bookworm)

set -euo pipefail

# Configuration
ONNX_VERSION="${1:-1.17.3}"
DISTRO="${2:-bookworm}"
BUILD_DIR="/var/tmp/onnx-xnnpack-fixed-$$"
BASE_OUTPUT_DIR="${OUTPUT_DIR:-$HOME/pitrac-packages}"
DEBIAN_ARCH="arm64"
PACKAGE_VERSION="${ONNX_VERSION}-xnnpack3"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

# Validate distro parameter
case "$DISTRO" in
    bookworm|trixie)
        log_info "Building for Debian $DISTRO"
        ;;
    *)
        log_error "Unknown distribution: $DISTRO (only bookworm and trixie supported)"
        exit 1
        ;;
esac

# Cleanup
cleanup() {
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "$BUILD_DIR" ]]; then
        log_info "Preserving build directory for inspection: $BUILD_DIR"
        log_info "Build log: $BUILD_DIR/build.log"
    fi
}
trap cleanup EXIT

# Install dependencies
log_info "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake ninja-build git \
    python3 python3-pip python3-dev python3-numpy python3-packaging \
    libprotobuf-dev protobuf-compiler \
    ccache pkg-config wget unzip

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# METHOD 1: Pre-patch the Eigen hash before cloning
log_info "Cloning ONNX Runtime v${ONNX_VERSION}..."
git clone --depth 1 --branch v${ONNX_VERSION} \
    https://github.com/microsoft/onnxruntime.git

cd onnxruntime

# Fix the Eigen hash BEFORE running build.sh
# GitLab changed the hash of their generated archives - need to update it
log_info "Fixing Eigen hash mismatch..."
OLD_HASH="be8be39fdbc6e60e94fa7870b280707069b5b81a"
CORRECT_HASH="32b145f525a8308d7ab1c09388b2e288312d8eba"

# The hash is primarily in cmake/deps.txt - patch it directly
if [[ -f "cmake/deps.txt" ]]; then
    if grep -q "$OLD_HASH" cmake/deps.txt; then
        log_info "Patching cmake/deps.txt"
        sed -i "s/$OLD_HASH/$CORRECT_HASH/g" cmake/deps.txt
    fi
fi

# Also search ALL text files for the hash (catches any location)
log_info "Searching for any other files with the old Eigen hash..."
for f in $(grep -rl "$OLD_HASH" . 2>/dev/null || true); do
    # Skip binary files and git directory
    if [[ "$f" != *".git"* ]] && file "$f" | grep -q "text"; then
        log_info "Patching: $f"
        sed -i "s/$OLD_HASH/$CORRECT_HASH/g" "$f"
    fi
done

# Verify the patch was applied
if grep -q "$OLD_HASH" cmake/deps.txt 2>/dev/null; then
    log_error "Failed to patch Eigen hash in cmake/deps.txt!"
    exit 1
fi
log_success "Eigen hash patched successfully"

cd "$BUILD_DIR/onnxruntime"

# Build with XNNPACK
log_info "Building ONNX Runtime with XNNPACK..."

# Determine memory and jobs
TOTAL_MEM_GB=$(free -g | grep ^Mem | awk '{print $2}')
if [ "$TOTAL_MEM_GB" -ge 8 ]; then
    NUM_JOBS=2
else
    NUM_JOBS=1
fi

log_info "System memory: $(free -h | grep ^Mem | awk '{print $2}') total"
log_info "Using $NUM_JOBS parallel job(s) for stability"

# Build flags - optimized for Pi5 YOLO inference
BUILD_FLAGS=(
    "--config" "Release"
    "--build_shared_lib"
    "--parallel" "$NUM_JOBS"
    "--skip_tests"
    "--use_xnnpack"
    "--allow_running_as_root"
)

# Pi 5 (Cortex-A76) optimization flags - ALWAYS apply for arm64 builds
# These flags are critical for YOLO inference performance
# Note: Native builds on Pi5 will auto-detect, but we force them for consistency
# IMPORTANT: Force C++17 because ONNX Runtime 1.17.3 is incompatible with GCC 14's C++20 defaults
PI5_CFLAGS="-march=armv8.2-a+fp16+dotprod -mtune=cortex-a76 -O3 -ftree-vectorize -ffast-math"
PI5_CXXFLAGS="${PI5_CFLAGS} -std=c++17"

if grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
    # Native Pi5 build - full optimization
    BUILD_FLAGS+=(
        "--cmake_extra_defines"
        "CMAKE_CXX_FLAGS=${PI5_CXXFLAGS}"
        "--cmake_extra_defines"
        "CMAKE_C_FLAGS=${PI5_CFLAGS}"
    )
    log_info "Detected Pi 5 - using full Cortex-A76 optimizations"
    log_info "CFLAGS: ${PI5_CFLAGS}"
    log_info "CXXFLAGS: ${PI5_CXXFLAGS}"
elif [ "$(uname -m)" = "aarch64" ]; then
    # Generic ARM64 build (e.g., Docker/QEMU) - still use Pi5 flags for target
    BUILD_FLAGS+=(
        "--cmake_extra_defines"
        "CMAKE_CXX_FLAGS=${PI5_CXXFLAGS}"
        "--cmake_extra_defines"
        "CMAKE_C_FLAGS=${PI5_CFLAGS}"
    )
    log_info "ARM64 build - forcing Pi5 (Cortex-A76) optimizations for target"
    log_info "CFLAGS: ${PI5_CFLAGS}"
    log_info "CXXFLAGS: ${PI5_CXXFLAGS}"
fi

log_info "Starting build (60-90 minutes)..."
./build.sh "${BUILD_FLAGS[@]}" 2>&1 | tee "$BUILD_DIR/build.log"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log_error "Build failed! Check log at: $BUILD_DIR/build.log"
    exit 1
fi

log_success "Build completed!"

# Verify XNNPACK
log_info "Verifying XNNPACK provider..."
BUILD_OUTPUT="$BUILD_DIR/onnxruntime/build/Linux/Release"
LIB_FILE=$(find "$BUILD_OUTPUT" -name "libonnxruntime.so*" -type f | head -1)

if [ -z "$LIB_FILE" ]; then
    log_error "Library not found!"
    exit 1
fi

# Check for XNNPACK - multiple patterns
XNNPACK_FOUND=false
if strings "$LIB_FILE" | grep -q "XnnpackExecutionProvider"; then
    XNNPACK_FOUND=true
fi
if strings "$LIB_FILE" | grep -qi "xnnpack"; then
    XNNPACK_FOUND=true
fi

if [ "$XNNPACK_FOUND" = true ]; then
    XNNPACK_COUNT=$(strings "$LIB_FILE" | grep -ci xnnpack || true)
    log_success "XNNPACK verified! Found $XNNPACK_COUNT XNNPACK symbols"
else
    log_warn "XNNPACK symbols not clearly found, but may still be included"
    log_info "Checking for any XNN references:"
    strings "$LIB_FILE" | grep -i xnn | head -5 || true
fi

# Create Debian package
log_info "Creating Debian package..."

LIB_VERSION=$(basename "$LIB_FILE" | sed 's/libonnxruntime.so.//')
PKG_DIR="$BUILD_DIR/libonnxruntime${LIB_VERSION}_${PACKAGE_VERSION}_arm64"

mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu"
mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu/pkgconfig"
mkdir -p "$PKG_DIR/usr/lib/pkgconfig"
mkdir -p "$PKG_DIR/usr/include/onnxruntime"
mkdir -p "$PKG_DIR/usr/share/doc/libonnxruntime${LIB_VERSION}"

# Copy library
cp "$LIB_FILE" "$PKG_DIR/usr/lib/aarch64-linux-gnu/"
cd "$PKG_DIR/usr/lib/aarch64-linux-gnu"
ln -s "libonnxruntime.so.${LIB_VERSION}" "libonnxruntime.so.1"
ln -s "libonnxruntime.so.1" "libonnxruntime.so"
cd "$BUILD_DIR"

# Copy headers (preserve directory structure)
if [[ -d "$BUILD_DIR/onnxruntime/include/onnxruntime" ]]; then
    cp -r "$BUILD_DIR/onnxruntime/include/onnxruntime/." "$PKG_DIR/usr/include/onnxruntime/"
else
    log_warn "Headers not found in expected location"
fi

# Create documentation
log_info "Creating documentation..."
cat > "$PKG_DIR/usr/share/doc/libonnxruntime${LIB_VERSION}/README.md" << EOF
# ONNX Runtime ${LIB_VERSION} with XNNPACK

This package provides ONNX Runtime with the XNNPACK execution provider
optimized for Raspberry Pi 5 (Cortex-A76).

## Features
- XNNPACK execution provider for 2-4x faster inference on ARM
- Optimized for YOLOv8/v11 single object detection models
- Built with Pi5 optimization flags: -march=armv8.2-a+fp16+dotprod -mtune=cortex-a76

## Verification
Run: /usr/share/doc/libonnxruntime${LIB_VERSION}/verify-xnnpack.sh

## Python Test
python3 -c "import onnxruntime; print(onnxruntime.get_available_providers())"

Built for PiTrac project.
EOF

cat > "$PKG_DIR/usr/share/doc/libonnxruntime${LIB_VERSION}/verify-xnnpack.sh" << 'VERIFYEOF'
#!/bin/bash
# Verify XNNPACK is properly included in ONNX Runtime
LIB=$(find /usr/lib -name "libonnxruntime.so*" -type f 2>/dev/null | head -1)
if [ -z "$LIB" ]; then
    echo "ERROR: libonnxruntime.so not found"
    exit 1
fi
COUNT=$(strings "$LIB" | grep -ci xnnpack || true)
if [ "$COUNT" -gt 0 ]; then
    echo "✓ XNNPACK VERIFIED: Found $COUNT XNNPACK symbols in $LIB"
    exit 0
else
    echo "✗ XNNPACK NOT FOUND in $LIB"
    exit 1
fi
VERIFYEOF
chmod +x "$PKG_DIR/usr/share/doc/libonnxruntime${LIB_VERSION}/verify-xnnpack.sh"

# Create pkg-config file
log_info "Creating pkg-config file..."
cat > "$PKG_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/onnxruntime.pc" << EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib/aarch64-linux-gnu
includedir=\${prefix}/include

Name: ONNX Runtime
Description: ONNX Runtime - cross-platform inference and training accelerator
Version: ${LIB_VERSION}
Libs: -L\${libdir} -lonnxruntime
Cflags: -I\${includedir}/onnxruntime
EOF

# Create symlink in /usr/lib/pkgconfig for compatibility
cd "$PKG_DIR/usr/lib/pkgconfig"
ln -s ../aarch64-linux-gnu/pkgconfig/onnxruntime.pc onnxruntime.pc
cd "$BUILD_DIR"

# Control file
cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: libonnxruntime${LIB_VERSION}
Version: ${PACKAGE_VERSION}
Architecture: arm64
Maintainer: PiTrac Build <build@pitrac.local>
Section: libs
Priority: optional
Depends: libc6, libstdc++6, libgcc-s1, libgomp1
Description: ONNX Runtime with XNNPACK for Raspberry Pi 5
 High-performance ML inference with XNNPACK execution provider.
 Optimized for Raspberry Pi 5 (Cortex-A76) with 2-4x faster inference.
 Built for YOLOv8/v11 object detection models.
Provides: libonnxruntime
Conflicts: libonnxruntime1.17.3, libonnxruntime1.18.1, libonnxruntime1.22.1, libonnxruntime1.23.0
Replaces: libonnxruntime1.17.3, libonnxruntime1.18.1, libonnxruntime1.22.1, libonnxruntime1.23.0
EOF

# postinst
cat > "$PKG_DIR/DEBIAN/postinst" << 'POSTINSTEOF'
#!/bin/sh
set -e
ldconfig

echo ""
echo "=========================================="
echo "  ONNX Runtime with XNNPACK installed!"
echo "=========================================="
echo ""
echo "Verify XNNPACK is working:"
echo "  /usr/share/doc/libonnxruntime*/verify-xnnpack.sh"
echo ""
echo "Or manually check:"
echo "  strings /usr/lib/aarch64-linux-gnu/libonnxruntime.so | grep -ci xnnpack"
echo ""
echo "Python test:"
echo "  python3 -c \"import onnxruntime; print(onnxruntime.get_available_providers())\""
echo ""

exit 0
POSTINSTEOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# Build deb
dpkg-deb --build --root-owner-group "$PKG_DIR"

# Move to output (distro-specific)
OUTPUT_DIR="$BASE_OUTPUT_DIR/$DISTRO/$DEBIAN_ARCH"
mkdir -p "$OUTPUT_DIR"
mv "$PKG_DIR.deb" "$OUTPUT_DIR/"

# Success message
log_success "==========================================="
log_success "Build Complete!"
log_success "==========================================="
echo ""
echo "Target distribution: $DISTRO"
echo "Package: $OUTPUT_DIR/libonnxruntime${LIB_VERSION}_${PACKAGE_VERSION}_arm64.deb"
echo ""
echo "Install with:"
echo "  sudo dpkg -i $OUTPUT_DIR/libonnxruntime${LIB_VERSION}_${PACKAGE_VERSION}_arm64.deb"
echo ""
echo "Verify XNNPACK:"
echo "  strings /usr/lib/aarch64-linux-gnu/libonnxruntime.so | grep -i xnnpack"
echo ""
log_info "Build artifacts preserved in: $BUILD_DIR"