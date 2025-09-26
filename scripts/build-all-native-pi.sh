#!/bin/bash
# Master script to build all PiTrac dependency packages natively on Raspberry Pi
# This avoids QEMU issues by building directly on ARM64 hardware

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/pitrac-packages}"

# Check if running on Raspberry Pi
check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        log_error "This script must be run on a Raspberry Pi"
        log_error "Use the Docker-based build system for cross-compilation"
        exit 1
    fi

    log_success "Running on Raspberry Pi - native build mode"
}

# Build OpenCV packages
build_opencv() {
    log_info "Building OpenCV packages..."
    if [[ -x "$SCRIPT_DIR/build-opencv-native-pi.sh" ]]; then
        OUTPUT_DIR="$OUTPUT_DIR" "$SCRIPT_DIR/build-opencv-native-pi.sh"
    else
        log_error "OpenCV build script not found"
        return 1
    fi
}

# Build ActiveMQ-CPP packages
build_activemq() {
    log_info "Building ActiveMQ-CPP packages..."
    if [[ -x "$SCRIPT_DIR/build-activemq-native-pi.sh" ]]; then
        OUTPUT_DIR="$OUTPUT_DIR" "$SCRIPT_DIR/build-activemq-native-pi.sh"
    else
        log_error "ActiveMQ build script not found"
        return 1
    fi
}

# Build lgpio package (if needed)
build_lgpio() {
    log_info "Checking if lgpio package is needed..."
    if dpkg -l | grep -q "^ii  liblgpio1"; then
        log_info "System lgpio package found, skipping build"
        return 0
    fi

    log_warn "lgpio not found in system packages"
    log_info "You may need to build lgpio manually or install from apt"
    # TODO: Add lgpio build script if needed
}

# Build msgpack package (if needed)
build_msgpack() {
    log_info "Checking if msgpack-cxx package is needed..."
    if dpkg -l | grep -q "^ii  libmsgpack-cxx-dev"; then
        log_info "System msgpack-cxx package found, skipping build"
        return 0
    fi

    log_warn "msgpack-cxx not found in system packages"
    log_info "You may need to build msgpack manually or install from apt"
    # TODO: Add msgpack build script if needed
}

# Copy packages to repository structure
organize_packages() {
    log_info "Organizing packages for repository..."

    REPO_DIR="$OUTPUT_DIR/repo"
    mkdir -p "$REPO_DIR/pool/main"

    # Copy all .deb files to pool
    if ls "$OUTPUT_DIR"/*.deb 1>/dev/null 2>&1; then
        cp "$OUTPUT_DIR"/*.deb "$REPO_DIR/pool/main/"

        log_success "Packages copied to repository structure:"
        ls -la "$REPO_DIR/pool/main/"*.deb
    else
        log_warn "No packages found to organize"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [PACKAGES]"
    echo ""
    echo "Build PiTrac dependency packages natively on Raspberry Pi"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help      Show this help message"
    echo "  -o, --output    Output directory (default: ~/pitrac-packages)"
    echo "  -c, --clean     Clean output directory before building"
    echo ""
    echo "PACKAGES:"
    echo "  all             Build all packages (default)"
    echo "  opencv          Build only OpenCV packages"
    echo "  activemq        Build only ActiveMQ-CPP packages"
    echo "  lgpio           Build only lgpio package"
    echo "  msgpack         Build only msgpack package"
    echo ""
    echo "Examples:"
    echo "  $0              # Build all packages"
    echo "  $0 opencv       # Build only OpenCV"
    echo "  $0 -c all       # Clean build all packages"
}

# Main execution
main() {
    log_info "PiTrac Native Package Builder for Raspberry Pi"
    echo ""

    # Check we're on a Pi
    check_raspberry_pi

    # Parse arguments
    CLEAN_BUILD=false
    PACKAGES=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_BUILD=true
                shift
                ;;
            *)
                PACKAGES="$PACKAGES $1"
                shift
                ;;
        esac
    done

    # Default to all packages
    if [[ -z "$PACKAGES" ]]; then
        PACKAGES="all"
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Clean if requested
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        log_warn "Cleaning output directory..."
        rm -f "$OUTPUT_DIR"/*.deb
    fi

    # Build requested packages
    for pkg in $PACKAGES; do
        case $pkg in
            all)
                build_opencv
                build_activemq
                build_lgpio
                build_msgpack
                ;;
            opencv)
                build_opencv
                ;;
            activemq)
                build_activemq
                ;;
            lgpio)
                build_lgpio
                ;;
            msgpack)
                build_msgpack
                ;;
            *)
                log_error "Unknown package: $pkg"
                show_usage
                exit 1
                ;;
        esac
    done

    # Organize packages
    organize_packages

    echo ""
    log_success "Native build complete!"
    log_info "Packages are in: $OUTPUT_DIR"
    echo ""
    log_info "To use these packages in the main build system:"
    log_info "1. Copy the .deb files to your development machine"
    log_info "2. Place them in: pitrac/packages/build/debs/arm64/"
    log_info "3. Run the main PiTrac build: make pitrac-package"
}

# Run main
main "$@"