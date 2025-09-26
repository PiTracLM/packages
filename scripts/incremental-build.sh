#!/usr/bin/env bash
# Incremental build script - only builds packages that have changed
# Usage: ./incremental-build.sh [package...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
CACHE_DIR="$BUILD_DIR/cache"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

declare -A PACKAGES=(
    ["lgpio"]="0.2.2-1"
    ["msgpack"]="6.1.1-1"
    ["activemq"]="3.9.5-1"
    ["opencv"]="4.11.0-1"
    ["pitrac"]="$(date +%Y.%m.%d)-1"
)

declare -A PACKAGE_SOURCES=(
    ["lgpio"]="docker/Dockerfile.lgpio"
    ["msgpack"]="docker/Dockerfile.msgpack"
    ["activemq"]="docker/Dockerfile.activemq"
    ["opencv"]="docker/Dockerfile.opencv"
    ["pitrac"]="docker/Dockerfile.pitrac:pitrac/:opencv/"
)

declare -A PACKAGE_DEPS=(
    ["lgpio"]=""
    ["msgpack"]=""
    ["activemq"]=""
    ["opencv"]=""
    ["pitrac"]="lgpio msgpack activemq opencv"
)

mkdir -p "$CACHE_DIR"

calculate_source_hash() {
    local package="$1"
    local source_paths="${PACKAGE_SOURCES[$package]}"
    local hash_input=""

    IFS=':' read -ra paths <<< "$source_paths"
    for path in "${paths[@]}"; do
        if [ -f "$PROJECT_ROOT/$path" ]; then
            hash_input+=$(md5sum "$PROJECT_ROOT/$path" | cut -d' ' -f1)
        elif [ -d "$PROJECT_ROOT/$path" ]; then
            hash_input+=$(find "$PROJECT_ROOT/$path" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
        fi
    done

    for dep in ${PACKAGE_DEPS[$package]}; do
        if [ -f "$CACHE_DIR/${dep}.hash" ]; then
            hash_input+=$(cat "$CACHE_DIR/${dep}.hash")
        fi
    done

    echo -n "$hash_input" | md5sum | cut -d' ' -f1
}

needs_rebuild() {
    local package="$1"
    local current_hash
    current_hash=$(calculate_source_hash "$package")

    if [ ! -f "$CACHE_DIR/${package}.hash" ]; then
        log_info "$package: No previous build found" >&2
        return 0
    fi

    local cached_hash
    cached_hash=$(cat "$CACHE_DIR/${package}.hash")

    if [ "$current_hash" != "$cached_hash" ]; then
        log_info "$package: Source changes detected" >&2
        return 0
    fi

    local deb_count
    deb_count=$(find "$BUILD_DIR/debs" -name "${package}*.deb" 2>/dev/null | wc -l)
    if [ "$deb_count" -eq 0 ]; then
        log_info "$package: No .deb files found" >&2
        return 0
    fi

    log_info "$package: No changes detected, skipping build" >&2
    return 1
}

update_package_hash() {
    local package="$1"
    local hash
    hash=$(calculate_source_hash "$package")
    echo "$hash" > "$CACHE_DIR/${package}.hash"
}

build_if_needed() {
    local package="$1"

    if [[ ! -v "PACKAGES[$package]" ]]; then
        log_error "Unknown package: $package"
        return 1
    fi

    local version="${PACKAGES[$package]}"

    if needs_rebuild "$package"; then
        log_info "Building $package..."

        for arch in arm64; do
            log_info "Building $package for $arch..."
            if ! "$SCRIPT_DIR/build-package.sh" "$package" "$arch" "$version"; then
                log_error "Failed to build $package for $arch"
                return 1
            fi
        done

        update_package_hash "$package"
        log_success "$package build completed"
    else
        log_success "$package is up to date"
    fi
}

get_build_order() {
    local -a requested_packages=("$@")
    local -a build_order=()
    local -a remaining_packages=()

    if [ ${#requested_packages[@]} -eq 0 ]; then
        requested_packages=(lgpio msgpack activemq opencv pitrac)
    fi

    for package in "${!PACKAGES[@]}"; do
        if needs_rebuild "$package"; then
            if [[ ! " ${requested_packages[*]} " =~ " ${package} " ]]; then
                requested_packages+=("$package")
                log_info "Adding $package to build queue due to changes" >&2
            fi
        fi
    done

    remaining_packages=("${requested_packages[@]}")

    while [ ${#remaining_packages[@]} -gt 0 ]; do
        local added_any=false
        local -a new_remaining=()

        for package in "${remaining_packages[@]}"; do
            local can_build=true

            if [[ ! -v "PACKAGE_DEPS[$package]" ]]; then
                log_error "Package $package not found in PACKAGE_DEPS"
                return 1
            fi

            for dep in ${PACKAGE_DEPS[$package]}; do
                if [[ ! " ${build_order[*]} " =~ " ${dep} " ]]; then
                    can_build=false
                    break
                fi
            done

            if [ "$can_build" = true ]; then
                build_order+=("$package")
                added_any=true
            else
                new_remaining+=("$package")
            fi
        done

        if [ "$added_any" = false ] && [ ${#new_remaining[@]} -gt 0 ]; then
            log_error "Circular dependency detected or missing dependencies for: ${new_remaining[*]}"
            return 1
        fi

        remaining_packages=("${new_remaining[@]}")
    done

    echo "${build_order[@]}"
}

main() {
    log_info "PiTrac Incremental Build System"

    make -C "$PROJECT_ROOT" setup check-docker

    local -a build_order
    if ! build_order=($(get_build_order "$@")); then
        exit 1
    fi

    if [ ${#build_order[@]} -eq 0 ]; then
        log_success "All packages are up to date"
        return 0
    fi

    log_info "Build order: ${build_order[*]}"

    for package in "${build_order[@]}"; do
        if ! build_if_needed "$package"; then
            log_error "Build failed for $package"
            exit 1
        fi
    done

    log_success "Incremental build completed successfully"

    echo ""
    log_info "Build Summary:"
    for package in "${build_order[@]}"; do
        local deb_count
        deb_count=$(find "$BUILD_DIR/debs" -name "${package}*.deb" 2>/dev/null | wc -l)
        echo "  $package: $deb_count packages built"
    done
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [package...]"
    echo ""
    echo "Build packages incrementally based on source changes."
    echo "If no packages specified, all changed packages will be built."
    echo ""
    echo "Available packages: ${!PACKAGES[*]}"
    echo ""
    echo "Examples:"
    echo "  $0                  # Build all changed packages"
    echo "  $0 pitrac           # Build pitrac and its dependencies if changed"
    echo "  $0 opencv pitrac    # Build opencv and pitrac if changed"
    exit 0
fi

main "$@"