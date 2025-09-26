#!/bin/bash
# Native Raspberry Pi 5 build script for ActiveMQ-CPP deb packages
# This script builds ActiveMQ-CPP directly on Pi hardware, avoiding QEMU issues
# Produces identical packages to the Docker build

set -euo pipefail

# Version configuration
ACTIVEMQ_VERSION="3.9.5"
PACKAGE_VERSION="3.9.5-1"
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
    sudo apt-get install -y \
        build-essential \
        dpkg-dev \
        debhelper \
        fakeroot \
        wget \
        tar \
        autoconf \
        automake \
        autotools-dev \
        libtool \
        pkg-config \
        libssl-dev \
        libapr1-dev \
        libaprutil1-dev \
        uuid-dev \
        libcppunit-dev \
        ccache

    log_success "Dependencies installed"
}

# Download ActiveMQ-CPP source
download_activemq() {
    log_info "Downloading ActiveMQ-CPP ${ACTIVEMQ_VERSION} source..."

    BUILD_DIR="/tmp/activemq-build-$$"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Download source
    if [[ ! -f "activemq-cpp-library-${ACTIVEMQ_VERSION}-src.tar.gz" ]]; then
        wget -q "https://archive.apache.org/dist/activemq/activemq-cpp/${ACTIVEMQ_VERSION}/activemq-cpp-library-${ACTIVEMQ_VERSION}-src.tar.gz"
    fi

    # Extract
    log_info "Extracting source archive..."
    tar -xzf "activemq-cpp-library-${ACTIVEMQ_VERSION}-src.tar.gz"
    mv "activemq-cpp-library-${ACTIVEMQ_VERSION}" activemq-cpp

    log_success "Source code ready"
}

# Configure and build ActiveMQ-CPP
build_activemq() {
    log_info "Configuring ActiveMQ-CPP build..."

    cd "$BUILD_DIR/activemq-cpp"

    # Run autogen
    ./autogen.sh

    # Set compiler flags based on Pi model
    if [[ "$PI_MODEL" == "pi5" ]]; then
        # Pi 5 with Cortex-A76 - use full optimizations on native hardware
        export CFLAGS="-mcpu=cortex-a76 -O3 -fomit-frame-pointer -pipe"
        export CXXFLAGS="-mcpu=cortex-a76 -O3 -fomit-frame-pointer -pipe"
    elif [[ "$PI_MODEL" == "pi4" ]]; then
        # Pi 4 with Cortex-A72
        export CFLAGS="-mcpu=cortex-a72 -O3 -fomit-frame-pointer -pipe"
        export CXXFLAGS="-mcpu=cortex-a72 -O3 -fomit-frame-pointer -pipe"
    else
        # Generic ARM64
        export CFLAGS="-march=armv8-a -O2 -pipe"
        export CXXFLAGS="-march=armv8-a -O2 -pipe"
    fi

    export LDFLAGS="-Wl,--as-needed"

    # Use ccache to speed up rebuilds
    export CC="ccache gcc"
    export CXX="ccache g++"
    export CCACHE_DIR="/tmp/ccache"

    # Configure
    log_info "Running configure..."
    ./configure \
        --prefix=/usr \
        --libdir=/usr/lib \
        --disable-ssl \
        --disable-static \
        --enable-shared \
        --with-apr=/usr \
        --disable-dependency-tracking

    # Build with parallel jobs
    log_info "Building ActiveMQ-CPP (this may take a while)..."
    NPROC=$(nproc)

    # Try with all cores first, then reduce if it fails
    if ! make -j"$NPROC"; then
        log_warn "Build failed with $NPROC jobs, retrying with 2..."
        make clean
        if ! make -j2; then
            log_warn "Build failed with 2 jobs, trying single job..."
            make clean
            make -j1
        fi
    fi

    log_success "ActiveMQ-CPP built successfully"
}

# Create deb packages
create_packages() {
    log_info "Creating deb packages..."

    # Install to staging directory
    cd "$BUILD_DIR/activemq-cpp"
    DESTDIR="$BUILD_DIR/pkg"
    make DESTDIR="$DESTDIR" install

    # Create package directories
    PKG_DIR="$BUILD_DIR/libactivemq-cpp_${PACKAGE_VERSION}_${DEBIAN_ARCH}"
    PKG_DEV_DIR="$BUILD_DIR/libactivemq-cpp-dev_${PACKAGE_VERSION}_${DEBIAN_ARCH}"

    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/lib/aarch64-linux-gnu"
    mkdir -p "$PKG_DEV_DIR/DEBIAN"
    mkdir -p "$PKG_DEV_DIR/usr/include"
    mkdir -p "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu"
    mkdir -p "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig"

    # Split files between packages
    log_info "Splitting files between runtime and dev packages..."

    # Runtime package - shared libraries only
    cp "$DESTDIR"/usr/lib/*.so.* "$PKG_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true

    # Development package - headers, static libs, and .so symlinks
    cp -r "$DESTDIR/usr/include"/* "$PKG_DEV_DIR/usr/include/"
    cp "$DESTDIR"/usr/lib/*.so "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
    cp "$DESTDIR"/usr/lib/*.a "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
    cp "$DESTDIR"/usr/lib/pkgconfig/* "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/" 2>/dev/null || true

    # Fix the pkg-config file to use correct lib directory
    if [[ -f "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/activemq-cpp.pc" ]]; then
        sed -i 's|/usr/lib|/usr/lib/aarch64-linux-gnu|g' "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/activemq-cpp.pc"
    fi

    # Create runtime package control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: libactivemq-cpp
Version: ${PACKAGE_VERSION}
Architecture: ${DEBIAN_ARCH}
Maintainer: PiTrac Build System <build@pitrac.org>
Section: libs
Priority: optional
Homepage: https://activemq.apache.org/components/cms/
Depends: libapr1, libaprutil1, libssl3
Description: ActiveMQ-CPP runtime libraries
 ActiveMQ-CPP is a C++ client library for Apache ActiveMQ.
 This package contains the runtime libraries.
EOF

    # Create development package control file
    cat > "$PKG_DEV_DIR/DEBIAN/control" << EOF
Package: libactivemq-cpp-dev
Version: ${PACKAGE_VERSION}
Architecture: ${DEBIAN_ARCH}
Maintainer: PiTrac Build System <build@pitrac.org>
Section: libdevel
Priority: optional
Homepage: https://activemq.apache.org/components/cms/
Depends: libactivemq-cpp (= ${PACKAGE_VERSION}), libapr1-dev, libaprutil1-dev, libssl-dev
Description: ActiveMQ-CPP development files
 ActiveMQ-CPP is a C++ client library for Apache ActiveMQ.
 This package contains the development files including headers and libraries.
EOF

    # Create pkg-config file if not already created
    if [[ ! -f "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/activemq-cpp.pc" ]]; then
        log_info "Creating pkg-config file..."
        cat > "$PKG_DEV_DIR/usr/lib/aarch64-linux-gnu/pkgconfig/activemq-cpp.pc" << 'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=/usr/lib/aarch64-linux-gnu
includedir=${prefix}/include

Name: activemq-cpp
Description: ActiveMQ-CPP Client Library
Version: 3.9.5
Libs: -L${libdir} -lactivemq-cpp
Libs.private: -lapr-1 -laprutil-1 -lssl -lcrypto -lpthread
Cflags: -I${includedir}
EOF
    fi

    # Create postinst for runtime package to run ldconfig
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        ldconfig
        ;;
    abort-upgrade|abort-remove|abort-deconfigure)
        ;;
    *)
        echo "postinst called with unknown argument: $1" >&2
        exit 1
        ;;
esac

exit 0
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postinst"

    # Create postrm for runtime package
    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    remove|purge)
        ldconfig
        ;;
    upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
        ;;
    *)
        echo "postrm called with unknown argument: $1" >&2
        exit 1
        ;;
esac

exit 0
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postrm"

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
    log_info "Native Raspberry Pi ActiveMQ-CPP Package Builder"
    log_info "Version: ${PACKAGE_VERSION}"

    # Set trap for cleanup
    trap cleanup EXIT

    # Check we're on a Pi
    check_raspberry_pi

    # Install dependencies
    install_dependencies

    # Download source
    download_activemq

    # Build ActiveMQ-CPP
    build_activemq

    # Create packages
    create_packages

    log_success "Build complete!"
    log_info "You can now copy the .deb files from $OUTPUT_DIR to your packaging repository"
}

# Run main
main "$@"