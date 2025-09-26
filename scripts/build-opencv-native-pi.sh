#!/bin/bash
# Native Raspberry Pi 5 build script for OpenCV 4.11.0 deb packages
# This script builds OpenCV directly on Pi hardware, avoiding QEMU issues
# Produces identical packages to the Docker build

set -euo pipefail

# Version configuration
OPENCV_VERSION="4.11.0"
PACKAGE_VERSION="4.11.0-1"
DEBIAN_ARCH="arm64"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

# Check if running on Raspberry Pi
check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        log_error "This script must be run on a Raspberry Pi"
        exit 1
    fi

    # Detect Pi model
    if grep -q "Raspberry Pi 5" /proc/cpuinfo; then
        log_info "Detected Raspberry Pi 5"
        PI_MODEL="pi5"
    elif grep -q "Raspberry Pi 4" /proc/cpuinfo; then
        log_info "Detected Raspberry Pi 4"
        PI_MODEL="pi4"
    else
        log_warn "Unknown Pi model, using generic ARM64 optimizations"
        PI_MODEL="generic"
    fi
}

# Install build dependencies
install_dependencies() {
    log_info "Installing build dependencies..."

    sudo apt-get update

    # Core dependencies that should always be available
    sudo apt-get install -y \
        build-essential \
        dpkg-dev \
        devscripts \
        fakeroot \
        dh-make \
        cmake \
        git \
        pkg-config \
        wget \
        unzip \
        zlib1g-dev \
        libgtk-3-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libxvidcore-dev \
        libx264-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        gfortran \
        openexr \
        libatlas-base-dev \
        python3-dev \
        python3-numpy \
        libtbb-dev \
        libdc1394-dev \
        libopenexr-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer1.0-dev \
        libglu1-mesa-dev \
        libgl1-mesa-dev \
        ccache

    # OpenCL dependencies - try to install what's available
    # Different Debian versions have different package names
    log_info "Installing OpenCL dependencies (if available)..."

    # Try to install OpenCL headers
    sudo apt-get install -y opencl-headers ocl-icd-opencl-dev 2>/dev/null || true

    # Try different versions of libopencl-clang-dev
    if ! dpkg -l | grep -q libopencl-clang; then
        # Try version-specific packages
        for version in 15 14 13 12 11; do
            if sudo apt-get install -y libopencl-clang-${version}-dev 2>/dev/null; then
                log_info "Installed libopencl-clang-${version}-dev"
                break
            fi
        done
    fi

    # Try to install clinfo for testing
    sudo apt-get install -y clinfo 2>/dev/null || true

    log_success "Dependencies installed"
}

# Download OpenCV source
download_opencv() {
    log_info "Downloading OpenCV ${OPENCV_VERSION} source..."

    BUILD_DIR="/tmp/opencv-build-$$"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Download OpenCV
    if [[ ! -f "opencv-${OPENCV_VERSION}.zip" ]]; then
        wget -q "https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip" -O "opencv-${OPENCV_VERSION}.zip"
    fi

    # Download OpenCV contrib
    if [[ ! -f "opencv_contrib-${OPENCV_VERSION}.zip" ]]; then
        wget -q "https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip" -O "opencv_contrib-${OPENCV_VERSION}.zip"
    fi

    # Extract
    log_info "Extracting source archives..."
    unzip -q "opencv-${OPENCV_VERSION}.zip"
    unzip -q "opencv_contrib-${OPENCV_VERSION}.zip"

    log_success "Source code ready"
}

# Configure and build OpenCV
build_opencv() {
    log_info "Configuring OpenCV build..."

    cd "$BUILD_DIR/opencv-${OPENCV_VERSION}"
    mkdir -p build
    cd build

    # Set compiler flags based on Pi model
    if [[ "$PI_MODEL" == "pi5" ]]; then
        # Pi 5 with Cortex-A76
        export CFLAGS="-mcpu=cortex-a76 -O3 -ftree-vectorize -fomit-frame-pointer -falign-functions=16 -falign-loops=16 -ffast-math"
        export CXXFLAGS="$CFLAGS"
    elif [[ "$PI_MODEL" == "pi4" ]]; then
        # Pi 4 with Cortex-A72
        export CFLAGS="-mcpu=cortex-a72 -O3 -ftree-vectorize -fomit-frame-pointer -falign-functions=16 -falign-loops=16 -ffast-math"
        export CXXFLAGS="$CFLAGS"
    else
        # Generic ARM64
        export CFLAGS="-march=armv8-a -O2 -pipe"
        export CXXFLAGS="$CFLAGS"
    fi

    # Use ccache to speed up rebuilds
    export CC="ccache gcc"
    export CXX="ccache g++"
    export CCACHE_DIR="/tmp/ccache"

    # Configure with CMake
    log_info "Running CMake configuration..."
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib/aarch64-linux-gnu \
        -DOPENCV_EXTRA_MODULES_PATH="../../opencv_contrib-${OPENCV_VERSION}/modules" \
        -DWITH_TBB=ON \
        -DWITH_V4L=ON \
        -DWITH_LIBV4L=ON \
        -DWITH_OPENGL=ON \
        -DWITH_OPENCL=OFF \
        -DWITH_FFMPEG=ON \
        -DWITH_NEON=ON \
        -DWITH_PNG=ON \
        -DWITH_JPEG=ON \
        -DWITH_TIFF=ON \
        -DWITH_GSTREAMER=ON \
        -DWITH_PROTOBUF=ON \
        -DWITH_OPENEXR=OFF \
        -DBUILD_TESTS=OFF \
        -DBUILD_PERF_TESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_DOCS=OFF \
        -DBUILD_PNG=OFF \
        -DBUILD_JPEG=OFF \
        -DBUILD_TIFF=OFF \
        -DBUILD_ZLIB=OFF \
        -DBUILD_JASPER=OFF \
        -DBUILD_WEBP=OFF \
        -DBUILD_OPENEXR=OFF \
        -DBUILD_opencv_python2=OFF \
        -DBUILD_opencv_python3=OFF \
        -DBUILD_opencv_java=OFF \
        -DBUILD_opencv_apps=OFF \
        -DBUILD_opencv_js=OFF \
        -DBUILD_LIST="core,imgproc,imgcodecs,calib3d,features2d,highgui,videoio,photo,dnn,objdetect,xfeatures2d,ximgproc,aruco" \
        -DCPU_BASELINE=DETECT \
        -DCPU_DISPATCH="" \
        -DENABLE_NEON=ON \
        -DOPENCV_DNN_OPENCL=OFF \
        -DOPENCV_ENABLE_NONFREE=ON \
        ..

    # Build with parallel jobs
    log_info "Building OpenCV (this will take a while)..."
    NPROC=$(nproc)
    make -j"$NPROC" || make -j2 || make -j1

    log_success "OpenCV built successfully"
}

# Create deb packages
create_packages() {
    log_info "Creating deb packages..."

    # Install to staging directory
    cd "$BUILD_DIR/opencv-${OPENCV_VERSION}/build"
    DESTDIR="$BUILD_DIR/pkg"
    make DESTDIR="$DESTDIR" install

    # Create package directories
    PKG_DIR="$BUILD_DIR/libopencv4.11_${PACKAGE_VERSION}_${DEBIAN_ARCH}"
    PKG_DEV_DIR="$BUILD_DIR/libopencv-dev_${PACKAGE_VERSION}_${DEBIAN_ARCH}"

    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu"
    mkdir -p "$PKG_DEV_DIR/DEBIAN"
    mkdir -p "$PKG_DEV_DIR/usr/include"
    mkdir -p "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu"
    mkdir -p "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig"

    # Split files between packages
    log_info "Splitting files between runtime and dev packages..."

    # Runtime package - shared libraries
    cp -r "$DESTDIR"/usr/lib/aarch64-linux-gnu/*.so.* "$PKG_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true

    # Development package - headers, static libs, pkg-config
    cp -r "$DESTDIR/usr/include"/* "$PKG_DEV_DIR/usr/include/" 2>/dev/null || true
    cp "$DESTDIR"/usr/lib/aarch64-linux-gnu/*.so "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
    cp "$DESTDIR"/usr/lib/aarch64-linux-gnu/*.a "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
    cp -r "$DESTDIR"/usr/lib/aarch64-linux-gnu/pkgconfig/* "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/" 2>/dev/null || true

    # Create pkg-config file for OpenCV4 if not already present
    if [[ ! -f "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/opencv4.pc" ]]; then
        log_info "Creating opencv4.pc pkg-config file..."
        cat > "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/opencv4.pc" << 'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib/aarch64-linux-gnu
includedir=${prefix}/include/opencv4

Name: OpenCV
Description: Open Source Computer Vision Library
Version: 4.11.0
Libs: -L${libdir} -lopencv_highgui -lopencv_objdetect -lopencv_photo -lopencv_calib3d -lopencv_features2d -lopencv_flann -lopencv_videoio -lopencv_imgcodecs -lopencv_imgproc -lopencv_core -lopencv_dnn -lopencv_xfeatures2d -lopencv_ximgproc -lopencv_aruco
Libs.private: -ldl -lm -lpthread -lrt
Cflags: -I${includedir}
EOF
    fi

    # Create runtime package control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: libopencv4.11
Version: ${PACKAGE_VERSION}
Architecture: ${DEBIAN_ARCH}
Maintainer: PiTrac Build System <build@pitrac.org>
Section: libs
Priority: optional
Homepage: https://opencv.org/
Depends: libgtk-3-0, libavcodec59 | libavcodec58, libavformat59 | libavformat58,
 libswscale6 | libswscale5, libtbb12, libgstreamer1.0-0,
 libgstreamer-plugins-base1.0-0, libopenexr-3-1-30 | libopenexr25,
 libjpeg62-turbo | libjpeg8, libpng16-16, libtiff6 | libtiff5
Description: OpenCV runtime libraries
 OpenCV (Open Source Computer Vision Library) is a library of programming
 functions mainly aimed at real-time computer vision.
 .
 This package contains the runtime libraries for OpenCV 4.11.0.
EOF

    # Create development package control file
    cat > "$PKG_DEV_DIR/DEBIAN/control" << EOF
Package: libopencv-dev
Version: ${PACKAGE_VERSION}
Architecture: ${DEBIAN_ARCH}
Maintainer: PiTrac Build System <build@pitrac.org>
Section: libdevel
Priority: optional
Homepage: https://opencv.org/
Depends: libopencv4.11 (= ${PACKAGE_VERSION}), libgtk-3-dev, libavcodec-dev,
 libavformat-dev, libswscale-dev, libtbb-dev, libgstreamer1.0-dev,
 libgstreamer-plugins-base1.0-dev
Description: OpenCV development files
 OpenCV (Open Source Computer Vision Library) is a library of programming
 functions mainly aimed at real-time computer vision.
 .
 This package contains the development files including headers and libraries
 needed to build applications using OpenCV.
EOF

    # Build the packages
    log_info "Building deb packages..."
    dpkg-deb --build --root-owner-group "$PKG_DIR"
    dpkg-deb --build --root-owner-group "$PKG_DEV_DIR"

    # Move packages to output directory
    OUTPUT_DIR="${OUTPUT_DIR:-$HOME/pitrac-packages}"
    mkdir -p "$OUTPUT_DIR"
    mv "$BUILD_DIR"/*.deb "$OUTPUT_DIR/"

    log_success "Packages created successfully"
    log_info "Packages saved to: $OUTPUT_DIR"
    ls -la "$OUTPUT_DIR"/*.deb
}

# Cleanup
cleanup() {
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

# Main execution
main() {
    log_info "Native Raspberry Pi OpenCV Package Builder"
    log_info "Version: ${PACKAGE_VERSION}"

    # Set trap for cleanup
    trap cleanup EXIT

    # Check we're on a Pi
    check_raspberry_pi

    # Install dependencies
    install_dependencies

    # Download source
    download_opencv

    # Build OpenCV
    build_opencv

    # Create packages
    create_packages

    log_success "Build complete!"
    log_info "You can now copy the .deb files from $OUTPUT_DIR to your packaging repository"
}

# Run main
main "$@"