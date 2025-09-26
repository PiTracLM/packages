#!/usr/bin/env bash
# Package builder script for PiTrac packages
# Usage: ./build-package.sh <package> <arch> <version>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DEB_DIR="$BUILD_DIR/debs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

if [ $# -ne 3 ]; then
    log_error "Usage: $0 <package> <arch> <version>"
    log_error "  package: lgpio|msgpack|activemq|opencv|pitrac"
    log_error "  arch: arm64"
    log_error "  version: package version (e.g., 1.0.0-1)"
    exit 1
fi

PACKAGE="$1"
ARCH="$2"
VERSION="$3"

case "$PACKAGE" in
    lgpio|msgpack|activemq|opencv|pitrac)
        ;;
    *)
        log_error "Unknown package: $PACKAGE"
        exit 1
        ;;
esac

case "$ARCH" in
    arm64)
        ;;
    *)
        log_error "Unknown architecture: $ARCH (only arm64 supported for Raspberry Pi 5)"
        exit 1
        ;;
esac

case "$ARCH" in
    arm64)
        DOCKER_PLATFORM="linux/arm64"
        DEBIAN_ARCH="arm64"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH (only arm64 supported)"
        exit 1
        ;;
esac

PACKAGE_DIR="$BUILD_DIR/$PACKAGE"
OUTPUT_DIR="$DEB_DIR/$ARCH"
DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile.$PACKAGE"
IMAGE_TAG="pitrac-$PACKAGE:$ARCH"

log_info "Building $PACKAGE for $ARCH (version $VERSION)"

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$DOCKERFILE" ]; then
    log_error "Dockerfile not found: $DOCKERFILE"
    exit 1
fi

log_info "Building Docker image: $IMAGE_TAG"

EXTRA_BUILD_ARGS=""
if [ "$PACKAGE" = "pitrac" ]; then
    if [ -n "${PITRAC_REPO:-}" ]; then
        EXTRA_BUILD_ARGS="$EXTRA_BUILD_ARGS --build-arg PITRAC_REPO=$PITRAC_REPO"
        log_info "Using PiTrac repository: $PITRAC_REPO"
    fi
    if [ -n "${PITRAC_BRANCH:-}" ]; then
        EXTRA_BUILD_ARGS="$EXTRA_BUILD_ARGS --build-arg PITRAC_BRANCH=$PITRAC_BRANCH"
        log_info "Using PiTrac branch: $PITRAC_BRANCH"
    fi
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        EXTRA_BUILD_ARGS="$EXTRA_BUILD_ARGS --build-arg GITHUB_TOKEN=$GITHUB_TOKEN"
        log_info "Using GitHub token for private repository access"
    fi
fi

docker build \
    --platform="$DOCKER_PLATFORM" \
    --build-arg DEBIAN_ARCH="$DEBIAN_ARCH" \
    --build-arg PACKAGE_VERSION="$VERSION" \
    $EXTRA_BUILD_ARGS \
    -f "$DOCKERFILE" \
    -t "$IMAGE_TAG" \
    "$PROJECT_ROOT"

log_info "Extracting .deb package from container"
CONTAINER_ID=$(docker create --platform="$DOCKER_PLATFORM" "$IMAGE_TAG")
TEMP_DIR="/tmp/pitrac-build-$$"

cleanup() {
    if [ -n "${CONTAINER_ID:-}" ]; then
        docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true
    fi
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT


if docker cp "$CONTAINER_ID:/output/" "$TEMP_DIR/" 2>/dev/null; then
    find "$TEMP_DIR" -name "*.deb" -exec mv {} "$OUTPUT_DIR/" \;
    rm -rf "$TEMP_DIR"
    log_success ".deb package extracted to $OUTPUT_DIR/"
elif docker cp "$CONTAINER_ID:/build/" "$TEMP_DIR/" 2>/dev/null; then
    find "$TEMP_DIR" -name "*.deb" -exec mv {} "$OUTPUT_DIR/" \;
    rm -rf "$TEMP_DIR"
    log_success ".deb package extracted to $OUTPUT_DIR/"
else
    log_error "Failed to extract .deb package from container"
    exit 1
fi

# Verify package was created
# Some packages have different naming patterns (e.g., liblgpio1 instead of lgpio)
DEB_FILE=$(find "$OUTPUT_DIR" -name "*${PACKAGE}*_${VERSION}_*.deb" -type f | head -1)
if [ -z "$DEB_FILE" ]; then
    DEB_FILE=$(find "$OUTPUT_DIR" -name "*${PACKAGE}*.deb" -type f | head -1)
fi

if [ -n "$DEB_FILE" ] && [ -f "$DEB_FILE" ]; then
    log_success "Package built: $(basename "$DEB_FILE")"
    log_info "Package info:"
    dpkg-deb -I "$DEB_FILE" | head -20
    log_info "Package size: $(du -h "$DEB_FILE" | cut -f1)"
else
    log_error "Package file not found in $OUTPUT_DIR"
    log_info "Available files:"
    ls -la "$OUTPUT_DIR" || true
    exit 1
fi

METADATA_FILE="$OUTPUT_DIR/${PACKAGE}_${ARCH}_${VERSION}.metadata"
cat > "$METADATA_FILE" << EOF
package: $PACKAGE
architecture: $ARCH
version: $VERSION
build_date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
build_host: $(hostname)
docker_platform: $DOCKER_PLATFORM
package_file: $(basename "$DEB_FILE")
package_size: $(stat -c%s "$DEB_FILE" 2>/dev/null || echo "unknown")
md5sum: $(md5sum "$DEB_FILE" | cut -d' ' -f1)
EOF

log_success "Build metadata saved: $METADATA_FILE"
log_success "Package $PACKAGE ($ARCH) built successfully"