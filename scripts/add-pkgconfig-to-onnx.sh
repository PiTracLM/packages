#!/bin/bash
# Add pkg-config files to existing ONNX Runtime packages
# This avoids the 60-90 minute rebuild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="/tmp/onnx-pkgconfig-patch-$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# Function to patch a single package
patch_package() {
    local deb_path="$1"
    local output_dir="$2"

    if [[ ! -f "$deb_path" ]]; then
        log_error "Package not found: $deb_path"
        return 1
    fi

    local deb_name=$(basename "$deb_path")
    local pkg_name="${deb_name%.deb}"

    log_info "Patching: $deb_name"

    # Create work directory
    local pkg_work="$WORK_DIR/$pkg_name"
    mkdir -p "$pkg_work"

    # Extract package (use absolute path for ar)
    cd "$pkg_work"
    local abs_deb_path="$REPO_ROOT/$deb_path"
    ar x "$abs_deb_path"

    # Extract control and data (handle both .gz and .xz compression)
    mkdir -p control data
    if [[ -f control.tar.xz ]]; then
        tar xJf control.tar.xz -C control
    elif [[ -f control.tar.gz ]]; then
        tar xzf control.tar.gz -C control
    fi

    if [[ -f data.tar.xz ]]; then
        tar xJf data.tar.xz -C data
    elif [[ -f data.tar.gz ]]; then
        tar xzf data.tar.gz -C data
    fi

    # Determine version from package name
    local version=""
    if [[ "$deb_name" =~ libonnxruntime([0-9.]+)_([0-9.]+-[^_]+)_ ]]; then
        version="${BASH_REMATCH[1]}"
    else
        log_error "Could not determine version from: $deb_name"
        return 1
    fi

    log_info "  Version detected: $version"

    # Create pkg-config directory
    mkdir -p "data/usr/lib/aarch64-linux-gnu/pkgconfig"

    # Create pkg-config file
    cat > "data/usr/lib/aarch64-linux-gnu/pkgconfig/onnxruntime.pc" << EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib/aarch64-linux-gnu
includedir=\${prefix}/include

Name: ONNX Runtime
Description: ONNX Runtime - cross-platform inference and training accelerator
Version: ${version}
Libs: -L\${libdir} -lonnxruntime
Cflags: -I\${includedir}/onnxruntime
EOF

    log_success "  Created pkg-config file"

    # Repackage data (use xz for consistency)
    cd data
    tar cJf ../data.tar.xz .
    cd ..

    # Repackage control
    cd control
    tar cJf ../control.tar.xz .
    cd ..

    # Build new deb
    ar rcs "${pkg_name}_patched.deb" debian-binary control.tar.xz data.tar.xz

    # Move to output
    mkdir -p "$output_dir"
    mv "${pkg_name}_patched.deb" "$output_dir/$deb_name"

    log_success "  Patched package: $output_dir/$deb_name"
}

# Main execution
main() {
    log_info "Patching ONNX Runtime packages with pkg-config files"
    echo ""

    cd "$REPO_ROOT"

    # Find all ONNX Runtime packages
    local packages=(
        pool/main/libo/libonnxruntime1.17.3/libonnxruntime1.17.3_1.17.3-xnnpack-verified_arm64.deb
        pool/main/libo/libonnxruntime1.17.3/libonnxruntime1.17.3_1.17.3-xnnpack-verified~trixie1_arm64.deb
        pool/main/libo/libonnxruntime1.22.1/libonnxruntime1.22.1_1.22.1-xnnpack3~trixie1_arm64.deb
    )

    local patched_count=0
    local failed_count=0

    for pkg in "${packages[@]}"; do
        if [[ -f "$pkg" ]]; then
            local output_dir=$(dirname "$pkg")
            local backup_dir="${output_dir}/backup-$(date +%Y%m%d-%H%M%S)"

            # Backup original
            mkdir -p "$backup_dir"
            cp "$pkg" "$backup_dir/"
            log_info "Backed up to: $backup_dir"

            # Patch
            if patch_package "$pkg" "$output_dir"; then
                ((patched_count++))
            else
                ((failed_count++))
            fi
            echo ""
        else
            log_warn "Package not found: $pkg"
            ((failed_count++))
        fi
    done

    # Summary
    log_success "========================================"
    log_success "Patching Complete!"
    log_success "========================================"
    echo ""
    echo "Patched: $patched_count packages"
    echo "Failed: $failed_count packages"
    echo ""

    if [[ $patched_count -gt 0 ]]; then
        log_info "Next steps:"
        echo "1. Verify packages:"
        echo "   dpkg-deb -c pool/main/libo/libonnxruntime1.22.1/libonnxruntime1.22.1_*.deb | grep onnxruntime.pc"
        echo ""
        echo "2. Update repository:"
        echo "   ./scripts/repo-update.sh . pool"
        echo ""
        echo "3. Commit and push:"
        echo "   git add pool/ dists/"
        echo "   git commit -m 'Add pkg-config files to ONNX Runtime packages'"
        echo "   git push"
    fi
}

main "$@"
