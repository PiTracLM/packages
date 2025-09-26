#!/usr/bin/env bash
# Comprehensive build orchestration script for PiTrac packages
# Usage: ./build-all.sh [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

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

# Default configuration
PACKAGES="all"
ARCHITECTURES="arm64"
FORCE_REBUILD=false
SKIP_TESTS=false
UPDATE_REPO=false
CLEAN_FIRST=false
PARALLEL_BUILDS=false
BUILD_TIMEOUT=3600  # 1 hour default

# Parse command line arguments
show_usage() {
    cat << 'EOF'
PiTrac Build Orchestration Script

Usage: ./build-all.sh [options]

Options:
  -p, --packages PKGS      Packages to build (default: all)
                           Available: lgpio, msgpack, activemq, opencv, pitrac, all
  -a, --arch ARCHS         Architectures to build (default: arm64)
                           Available: arm64 (Raspberry Pi 5 only)
  -f, --force              Force rebuild even if up to date
  -t, --skip-tests         Skip package testing
  -r, --update-repo        Update APT repository after build
  -c, --clean              Clean build environment first
  -j, --parallel           Build packages in parallel where possible
  --timeout SECONDS        Build timeout in seconds (default: 3600)
  -h, --help               Show this help message

Build Modes:
  incremental              Build only changed packages (default)
  full                     Build all packages regardless of changes
  clean                    Clean build environment and rebuild

Examples:
  ./build-all.sh                           # Incremental build of changed packages
  ./build-all.sh --packages pitrac         # Build only pitrac package
  ./build-all.sh --arch arm64 --force      # Force rebuild for arm64 only
  ./build-all.sh --clean --parallel        # Clean build with parallel execution
  ./build-all.sh --packages all --update-repo  # Full build and update repository

Environment Variables:
  DOCKER_BUILDKIT=1        Enable Docker BuildKit for faster builds
  BUILD_CACHE_DIR          Custom cache directory for incremental builds
  BUILD_WORKERS            Number of parallel build workers (default: 2)

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--packages)
            PACKAGES="$2"
            shift 2
            ;;
        -a|--arch)
            ARCHITECTURES="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_REBUILD=true
            shift
            ;;
        -t|--skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        -r|--update-repo)
            UPDATE_REPO=true
            shift
            ;;
        -c|--clean)
            CLEAN_FIRST=true
            shift
            ;;
        -j|--parallel)
            PARALLEL_BUILDS=true
            shift
            ;;
        --timeout)
            BUILD_TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate configuration
validate_config() {
    log_info "Validating build configuration..."

    # Check if required tools are available
    local required_tools=(docker make)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done

    # Validate packages
    if [ "$PACKAGES" = "all" ]; then
        PACKAGES="lgpio msgpack activemq opencv pitrac"
    fi

    for pkg in $PACKAGES; do
        case "$pkg" in
            lgpio|msgpack|activemq|opencv|pitrac)
                ;;
            *)
                log_error "Unknown package: $pkg"
                exit 1
                ;;
        esac
    done

    # Validate architectures
    for arch in $ARCHITECTURES; do
        case "$arch" in
            arm64)
                ;;
            *)
                log_error "Unknown architecture: $arch"
                exit 1
                ;;
        esac
    done

    log_success "Configuration validated"
}

# Setup build environment
setup_environment() {
    log_info "Setting up build environment..."

    # Set Docker BuildKit for faster builds
    export DOCKER_BUILDKIT=1

    # Setup build directories
    make setup

    # Check Docker and QEMU
    make check-docker

    # Set parallel workers
    if [ "$PARALLEL_BUILDS" = true ]; then
        export BUILD_WORKERS="${BUILD_WORKERS:-2}"
        log_info "Parallel builds enabled with $BUILD_WORKERS workers"
    fi

    log_success "Build environment ready"
}

# Clean build environment
clean_environment() {
    if [ "$CLEAN_FIRST" = true ]; then
        log_warn "Cleaning build environment..."
        make clean
        log_success "Build environment cleaned"
    fi
}

# Build packages with progress tracking
build_packages() {
    log_info "Starting package build process..."

    local build_start_time=$(date +%s)
    local -a build_jobs=()

    if [ "$FORCE_REBUILD" = true ]; then
        log_info "Force rebuild enabled - all packages will be rebuilt"
        # Use make targets directly
        for pkg in $PACKAGES; do
            for arch in $ARCHITECTURES; do
                if [ "$PARALLEL_BUILDS" = true ]; then
                    log_info "Starting build: $pkg-$arch"
                    timeout "$BUILD_TIMEOUT" make "build-$pkg-$arch" &
                    build_jobs+=($!)
                else
                    log_info "Building: $pkg-$arch"
                    timeout "$BUILD_TIMEOUT" make "build-$pkg-$arch"
                fi
            done
        done
    else
        # Use incremental build script
        log_info "Using incremental build for: $PACKAGES"
        if [ "$PARALLEL_BUILDS" = true ]; then
            timeout "$BUILD_TIMEOUT" ./scripts/incremental-build.sh $PACKAGES &
            build_jobs+=($!)
        else
            timeout "$BUILD_TIMEOUT" ./scripts/incremental-build.sh $PACKAGES
        fi
    fi

    # Wait for parallel builds to complete
    if [ "$PARALLEL_BUILDS" = true ] && [ ${#build_jobs[@]} -gt 0 ]; then
        log_info "Waiting for ${#build_jobs[@]} parallel build jobs to complete..."

        local failed_jobs=0
        for job in "${build_jobs[@]}"; do
            if ! wait "$job"; then
                ((failed_jobs++))
            fi
        done

        if [ "$failed_jobs" -gt 0 ]; then
            log_error "$failed_jobs build jobs failed"
            return 1
        fi
    fi

    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))

    log_success "Package build completed in ${build_duration}s"
}

# Test built packages
test_packages() {
    if [ "$SKIP_TESTS" = true ]; then
        log_info "Skipping package tests (--skip-tests specified)"
        return 0
    fi

    log_info "Testing built packages..."

    if [ -f scripts/test-packages.sh ]; then
        if ./scripts/test-packages.sh build/debs; then
            log_success "All packages passed testing"
        else
            log_error "Package testing failed"
            return 1
        fi
    else
        log_warn "Test script not found, skipping package tests"
    fi
}

# Update APT repository
update_repository() {
    if [ "$UPDATE_REPO" = true ]; then
        log_info "Updating APT repository..."

        # Initialize repository if needed
        if [ ! -d build/repo/conf ]; then
            log_info "Initializing APT repository..."
            make repo-init
        fi

        # Update repository with new packages
        if make repo-update; then
            log_success "APT repository updated"
        else
            log_error "Failed to update APT repository"
            return 1
        fi
    else
        log_info "Skipping repository update (use --update-repo to enable)"
    fi
}

# Generate build report
generate_report() {
    log_info "Generating build report..."

    local report_file="build/build-report-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p build

    cat > "$report_file" << EOF
# PiTrac Package Build Report

**Build Date:** $(date)
**Build Host:** $(hostname)
**Build User:** $(whoami)

## Configuration

- **Packages:** $PACKAGES
- **Architectures:** $ARCHITECTURES
- **Force Rebuild:** $FORCE_REBUILD
- **Parallel Builds:** $PARALLEL_BUILDS
- **Skip Tests:** $SKIP_TESTS
- **Update Repository:** $UPDATE_REPO

## Package Summary

EOF

    # Add package information
    if [ -d build/debs ]; then
        echo "### Built Packages" >> "$report_file"
        echo "" >> "$report_file"

        for arch in $ARCHITECTURES; do
            if [ -d "build/debs/$arch" ]; then
                echo "#### $arch Architecture" >> "$report_file"
                echo "" >> "$report_file"

                for deb in build/debs/$arch/*.deb; do
                    if [ -f "$deb" ]; then
                        local pkg_name=$(dpkg-deb -f "$deb" Package)
                        local pkg_version=$(dpkg-deb -f "$deb" Version)
                        local pkg_size=$(du -h "$deb" | cut -f1)

                        echo "- **$pkg_name** $pkg_version ($pkg_size)" >> "$report_file"
                    fi
                done
                echo "" >> "$report_file"
            fi
        done
    fi

    # Add repository information
    if [ "$UPDATE_REPO" = true ] && [ -d build/repo ]; then
        echo "### Repository Status" >> "$report_file"
        echo "" >> "$report_file"
        echo "APT repository updated successfully." >> "$report_file"
        echo "" >> "$report_file"
    fi

    # Add system information
    cat >> "$report_file" << EOF

## System Information

- **OS:** $(uname -s) $(uname -r)
- **Architecture:** $(uname -m)
- **Docker Version:** $(docker --version)
- **Available Memory:** $(free -h | awk '/^Mem:/ {print $2}')
- **Available Disk:** $(df -h . | awk 'NR==2 {print $4}')

## Build Environment

- **Build Directory:** $PROJECT_ROOT
- **Docker BuildKit:** ${DOCKER_BUILDKIT:-disabled}
- **Build Workers:** ${BUILD_WORKERS:-1}
- **Build Timeout:** ${BUILD_TIMEOUT}s

EOF

    log_success "Build report generated: $report_file"
}

# Cleanup function
cleanup() {
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_success "Build process completed successfully"
    else
        log_error "Build process failed with exit code $exit_code"
    fi

    # Cleanup any background jobs
    jobs -p | xargs -r kill 2>/dev/null || true

    exit $exit_code
}

# Main execution
main() {
    log_info "PiTrac Package Build Orchestration"
    log_info "=================================="
    echo ""

    # Set up signal handlers
    trap cleanup EXIT INT TERM

    # Record start time
    local start_time=$(date +%s)

    # Execute build pipeline
    validate_config
    clean_environment
    setup_environment
    build_packages
    test_packages
    update_repository
    generate_report

    # Calculate total time
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))

    echo ""
    log_success "Build orchestration completed successfully!"
    log_info "Total build time: ${total_duration}s"

    # Show next steps
    echo ""
    log_info "Next Steps:"
    echo "  - Check build report in build/ directory"
    echo "  - List built packages: make list-debs"

    if [ "$UPDATE_REPO" = true ]; then
        echo "  - Repository updated and ready for deployment"
    else
        echo "  - Update repository: make repo-update"
    fi

    echo ""
}

# Run main function
main "$@"