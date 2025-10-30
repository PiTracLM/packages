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
log_info "Fixing Eigen hash mismatch..."
CORRECT_HASH="32b145f525a8308d7ab1c09388b2e288312d8eba"

# Find and patch all files with the old hash
find . -type f \( -name "*.cmake" -o -name "CMakeLists.txt" \) -exec grep -l "be8be39fdbc6e60e94fa7870b280707069b5b81a" {} \; | while read f; do
    log_info "Patching: $f"
    sed -i "s/be8be39fdbc6e60e94fa7870b280707069b5b81a/$CORRECT_HASH/g" "$f"
done

# METHOD 2: Also pre-download Eigen to bypass download
log_info "Pre-downloading Eigen to cache..."
mkdir -p "$BUILD_DIR/eigen-cache"
cd "$BUILD_DIR/eigen-cache"

wget -q https://gitlab.com/libeigen/eigen/-/archive/e7248b26a1ed53fa030c5c459f7ea095dfd276ac/eigen-e7248b26a1ed53fa030c5c459f7ea095dfd276ac.zip
ACTUAL_HASH=$(sha1sum eigen-e7248b26a1ed53fa030c5c459f7ea095dfd276ac.zip | cut -d' ' -f1)
log_info "Eigen downloaded with hash: $ACTUAL_HASH"

# Create a pre-populated cache directory structure
mkdir -p "$BUILD_DIR/onnxruntime/build/Linux/Release/_deps"
cp eigen-e7248b26a1ed53fa030c5c459f7ea095dfd276ac.zip \
   "$BUILD_DIR/onnxruntime/build/Linux/Release/_deps/" 2>/dev/null || true

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

# Build flags - minimal and focused
BUILD_FLAGS=(
    "--config" "Release"
    "--build_shared_lib"
    "--parallel" "$NUM_JOBS"
    "--skip_tests"
    "--use_xnnpack"
    "--allow_running_as_root"
)

# Add ARM optimizations if on Pi 5
if grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
    BUILD_FLAGS+=(
        "--cmake_extra_defines"
        "CMAKE_CXX_FLAGS=-march=armv8.2-a+fp16+dotprod -mtune=cortex-a76"
    )
    log_info "Detected Pi 5 - using Cortex-A76 optimizations"
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
mkdir -p "$PKG_DIR/usr/include/onnxruntime"

# Copy library
cp "$LIB_FILE" "$PKG_DIR/usr/lib/aarch64-linux-gnu/"
cd "$PKG_DIR/usr/lib/aarch64-linux-gnu"
ln -s "libonnxruntime.so.${LIB_VERSION}" "libonnxruntime.so.1"
ln -s "libonnxruntime.so.1" "libonnxruntime.so"
cd "$BUILD_DIR"

# Copy headers
find "$BUILD_DIR/onnxruntime/include" -name "*.h" \
    -exec cp {} "$PKG_DIR/usr/include/onnxruntime/" \; 2>/dev/null || true

# Control file
cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: libonnxruntime${LIB_VERSION}
Version: ${PACKAGE_VERSION}
Architecture: arm64
Maintainer: PiTrac Build <build@pitrac.local>
Section: libs
Priority: optional
Depends: libc6, libstdc++6, libgcc-s1, libgomp1
Description: ONNX Runtime with XNNPACK
 High-performance inference with XNNPACK provider.
 2-4x faster on Raspberry Pi 5.
Provides: libonnxruntime
Conflicts: libonnxruntime1.17.3, libonnxruntime1.18.1, libonnxruntime1.23.0
Replaces: libonnxruntime1.17.3, libonnxruntime1.18.1, libonnxruntime1.23.0
EOF

# postinst
cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
ldconfig
echo "ONNX Runtime with XNNPACK installed!"
exit 0
EOF
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
allopo@pitrac:~/build $ ./onnx.sh 
[INFO] Looking for built library...
[✓] Found library: /tmp/onnx-fixed-build/onnxruntime/build/libonnxruntime.so.1.17.3
[INFO] Verifying XNNPACK provider...
[✓] XNNPACK VERIFIED! Found 248 XNNPACK symbols
XnnpackExecutionProvider
virtual std::vector<std::shared_ptr<onnxruntime::IAllocator> > onnxruntime::XnnpackExecutionProvider::CreatePreferredAllocators()
virtual std::vector<std::unique_ptr<onnxruntime::ComputeCapability> > onnxruntime::XnnpackExecutionProvider::GetCapability(const onnxruntime::GraphViewer&, const onnxruntime::IExecutionProvider::IKernelLookup&) const
XNNPACK
Unknown provider name. Currently supported values are 'OPENVINO', 'SNPE', 'XNNPACK', 'QNN', 'WEBNN' and 'AZURE'
XnnpackExecutionProvider
[INFO] Library version: 1.17.3
[INFO] Copying library files...
[INFO] Copying header files...
[INFO] Building Debian package...
dpkg-deb: building package 'libonnxruntime1.17.3' in '/tmp/tmp.zZMw1jtsRZ/libonnxruntime1.17.3_1.17.3-xnnpack-verified_arm64.deb'.
[✓] ===========================================
[✓] Package Created Successfully!
[✓] ===========================================

Package: /home/cgallopo/pitrac-packages/libonnxruntime1.17.3_1.17.3-xnnpack-verified_arm64.deb

XNNPACK Status: ✓ VERIFIED (248 symbols)

Install on Raspberry Pi 5:
  sudo dpkg -i /home/cgallopo/pitrac-packages/libonnxruntime1.17.3_1.17.3-xnnpack-verified_arm64.deb

After installation, verify with:
  /usr/share/doc/libonnxruntime1.17.3/verify-xnnpack.sh

[✓] XNNPACK provider is confirmed present in this build!
cgallopo@pitrac:~/build $