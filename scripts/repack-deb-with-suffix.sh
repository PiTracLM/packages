#!/bin/bash
#
# repack-deb-with-suffix.sh
#
# Repacks existing .deb files with distribution-specific version suffixes
# WITHOUT rebuilding from source.
#
# Usage: ./repack-deb-with-suffix.sh <deb-file> <distro> [suffix-num]
#
# Example:
#   ./repack-deb-with-suffix.sh liblgpio1_0.2.2-1_arm64.deb bookworm
#   Output: liblgpio1_0.2.2-1~bookworm1_arm64.deb
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 <deb-file> <distro> [suffix-num] [output-dir]

Arguments:
  deb-file    : Path to the .deb file to repack
  distro      : Distribution name (bookworm, trixie, etc.)
  suffix-num  : Optional suffix number (default: 1)
  output-dir  : Optional output directory (default: same as input)

Example:
  $0 liblgpio1_0.2.2-1_arm64.deb bookworm
  $0 liblgpio1_0.2.2-1_arm64.deb trixie 2 /output/path

Output:
  - Repacked .deb with modified version in filename
  - Log file showing changes made
EOF
    exit 1
}

# Check dependencies
check_dependencies() {
    local missing=0
    for cmd in dpkg-deb ar tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Please install missing dependencies"
        exit 1
    fi
}

# Validate .deb file
validate_deb() {
    local deb_file="$1"

    if [ ! -f "$deb_file" ]; then
        log_error "File not found: $deb_file"
        return 1
    fi

    if ! dpkg-deb -I "$deb_file" &> /dev/null; then
        log_error "Invalid .deb file: $deb_file"
        return 1
    fi

    return 0
}

# Extract control field value
get_control_field() {
    local control_file="$1"
    local field="$2"

    grep "^${field}:" "$control_file" | sed "s/^${field}: *//"
}

# Update control field
update_control_field() {
    local control_file="$1"
    local field="$2"
    local new_value="$3"

    sed -i "s|^${field}:.*|${field}: ${new_value}|" "$control_file"
}

# Check if version already has suffix
has_version_suffix() {
    local version="$1"
    local distro="$2"

    if [[ "$version" =~ ~${distro}[0-9]+ ]]; then
        return 0
    fi
    return 1
}

# Update version references in dependency fields
update_dependency_versions() {
    local control_file="$1"
    local package_name="$2"
    local old_version="$3"
    local new_version="$4"

    # Update Depends, Replaces, Conflicts, Breaks, Provides fields
    for field in Depends Replaces Conflicts Breaks Provides; do
        if grep -q "^${field}:" "$control_file"; then
            # Replace version references for the same package
            sed -i "s|\(${package_name}\) (= ${old_version})|\1 (= ${new_version})|g" "$control_file"
            sed -i "s|\(${package_name}\) (>= ${old_version})|\1 (>= ${new_version})|g" "$control_file"
            sed -i "s|\(${package_name}\) (<= ${old_version})|\1 (<= ${new_version})|g" "$control_file"

            # Also update cross-package dependencies for related packages
            # This is crucial for packages like libopencv-dev that depend on libopencv4.11
            # Both need to have matching version suffixes (e.g., ~trixie1)
            sed -i "s| (= ${old_version})| (= ${new_version})|g" "$control_file"
            sed -i "s| (>= ${old_version})| (>= ${new_version})|g" "$control_file"
            sed -i "s| (<= ${old_version})| (<= ${new_version})|g" "$control_file"
        fi
    done
}

# Detect compression type
detect_compression() {
    local tar_file="$1"

    if [[ "$tar_file" == *.tar.gz ]]; then
        echo "gzip"
    elif [[ "$tar_file" == *.tar.xz ]]; then
        echo "xz"
    elif [[ "$tar_file" == *.tar.zst ]]; then
        echo "zstd"
    else
        echo "unknown"
    fi
}

# Repack control archive
repack_control_archive() {
    local work_dir="$1"
    local control_dir="$2"
    local compression="$3"

    local control_tar
    case "$compression" in
        gzip)
            control_tar="control.tar.gz"
            (cd "$control_dir" && tar czf "$work_dir/$control_tar" ./*)
            ;;
        xz)
            control_tar="control.tar.xz"
            (cd "$control_dir" && tar cJf "$work_dir/$control_tar" ./*)
            ;;
        zstd)
            control_tar="control.tar.zst"
            (cd "$control_dir" && tar --zstd -cf "$work_dir/$control_tar" ./*)
            ;;
        *)
            log_error "Unknown compression type: $compression"
            return 1
            ;;
    esac

    echo "$control_tar"
}

# Main repack function
repack_deb() {
    local deb_file="$1"
    local distro="$2"
    local suffix_num="${3:-1}"
    local output_dir="${4:-}"

    # Validate input
    if ! validate_deb "$deb_file"; then
        return 1
    fi

    # Get absolute path
    deb_file=$(realpath "$deb_file")
    local deb_basename=$(basename "$deb_file")
    local deb_dir=$(dirname "$deb_file")

    # Set output directory
    if [ -z "$output_dir" ]; then
        output_dir="$deb_dir"
    else
        mkdir -p "$output_dir"
        output_dir=$(realpath "$output_dir")
    fi

    log_info "Processing: $deb_basename"
    log_info "Distribution: $distro (suffix: $suffix_num)"

    # Extract package info
    local package_name=$(dpkg-deb -f "$deb_file" Package)
    local current_version=$(dpkg-deb -f "$deb_file" Version)
    local architecture=$(dpkg-deb -f "$deb_file" Architecture)

    log_info "Package: $package_name"
    log_info "Current version: $current_version"
    log_info "Architecture: $architecture"

    # Check if version already has this suffix
    if has_version_suffix "$current_version" "$distro"; then
        log_warn "Version already has ~${distro} suffix: $current_version"
        log_warn "Skipping to avoid double-suffixing"
        return 0
    fi

    # Calculate new version
    local new_version="${current_version}~${distro}${suffix_num}"
    log_info "New version: $new_version"

    # Create temporary working directory
    local work_dir=$(mktemp -d -t repack-deb-XXXXXX)
    local extract_dir="$work_dir/extract"
    local control_dir="$work_dir/control"
    local log_file="$work_dir/repack.log"

    log_info "Working directory: $work_dir"

    # Set up cleanup trap
    trap "rm -rf '$work_dir'" EXIT

    mkdir -p "$extract_dir" "$control_dir"

    # Start logging
    {
        echo "==================================="
        echo "Repack Log"
        echo "==================================="
        echo "Date: $(date)"
        echo "Input: $deb_file"
        echo "Package: $package_name"
        echo "Old Version: $current_version"
        echo "New Version: $new_version"
        echo "Distribution: $distro"
        echo "==================================="
        echo ""
    } > "$log_file"

    # Extract the .deb file
    log_info "Extracting .deb archive..."
    cd "$extract_dir"
    ar x "$deb_file"

    # Find control archive
    local control_tar=""
    for f in control.tar.gz control.tar.xz control.tar.zst; do
        if [ -f "$extract_dir/$f" ]; then
            control_tar="$f"
            break
        fi
    done

    if [ -z "$control_tar" ]; then
        log_error "Could not find control archive in .deb"
        return 1
    fi

    log_info "Found control archive: $control_tar"
    local compression=$(detect_compression "$control_tar")
    log_info "Compression type: $compression"

    # Extract control archive
    log_info "Extracting control archive..."
    tar -xf "$extract_dir/$control_tar" -C "$control_dir"

    # Modify control file
    local control_file="$control_dir/control"
    if [ ! -f "$control_file" ]; then
        log_error "Control file not found: $control_file"
        return 1
    fi

    log_info "Updating control file..."

    # Backup original control file
    cp "$control_file" "$control_file.orig"

    # Update version
    update_control_field "$control_file" "Version" "$new_version"

    # Update dependency versions
    update_dependency_versions "$control_file" "$package_name" "$current_version" "$new_version"

    # Log changes
    {
        echo "Control file changes:"
        echo "---------------------"
        diff -u "$control_file.orig" "$control_file" || true
        echo ""
    } >> "$log_file"

    log_success "Control file updated"

    # Repack control archive
    log_info "Repacking control archive..."
    rm "$extract_dir/$control_tar"

    local new_control_tar=$(repack_control_archive "$extract_dir" "$control_dir" "$compression")
    if [ $? -ne 0 ]; then
        log_error "Failed to repack control archive"
        return 1
    fi

    log_success "Control archive repacked: $new_control_tar"

    # Rebuild .deb using ar
    log_info "Rebuilding .deb package..."

    # Find data archive
    local data_tar=""
    for f in data.tar.gz data.tar.xz data.tar.zst; do
        if [ -f "$extract_dir/$f" ]; then
            data_tar="$f"
            break
        fi
    done

    if [ -z "$data_tar" ]; then
        log_error "Could not find data archive in .deb"
        return 1
    fi

    # Construct new filename
    local new_deb_name="${package_name}_${new_version}_${architecture}.deb"
    local new_deb_path="$output_dir/$new_deb_name"

    log_info "Output file: $new_deb_name"

    # Build new .deb with ar
    cd "$extract_dir"
    ar rc "$new_deb_path" debian-binary "$new_control_tar" "$data_tar"

    if [ ! -f "$new_deb_path" ]; then
        log_error "Failed to create new .deb: $new_deb_path"
        return 1
    fi

    log_success "New .deb created: $new_deb_path"

    # Verify the new .deb
    log_info "Verifying new .deb..."
    if ! dpkg-deb -I "$new_deb_path" &> /dev/null; then
        log_error "New .deb is invalid!"
        return 1
    fi

    # Check version in new package
    local verify_version=$(dpkg-deb -f "$new_deb_path" Version)
    if [ "$verify_version" != "$new_version" ]; then
        log_error "Version mismatch! Expected: $new_version, Got: $verify_version"
        return 1
    fi

    log_success "Verification passed"

    # Display package info
    echo ""
    log_info "New package information:"
    dpkg-deb -I "$new_deb_path" | grep -E "^ (Package|Version|Architecture):"

    # Save log file
    local log_output="$output_dir/${package_name}_${new_version}_repack.log"
    cp "$log_file" "$log_output"
    log_info "Log saved to: $log_output"

    echo ""
    log_success "✓ Repack completed successfully"
    log_success "  Input:  $deb_basename"
    log_success "  Output: $new_deb_name"

    return 0
}

# Main script
main() {
    # Check arguments
    if [ $# -lt 2 ]; then
        usage
    fi

    local deb_file="$1"
    local distro="$2"
    local suffix_num="${3:-1}"
    local output_dir="${4:-}"

    # Check dependencies
    check_dependencies

    # Validate distribution name
    if [[ ! "$distro" =~ ^[a-z]+$ ]]; then
        log_error "Invalid distribution name: $distro"
        log_error "Distribution name should contain only lowercase letters"
        exit 1
    fi

    # Validate suffix number
    if [[ ! "$suffix_num" =~ ^[0-9]+$ ]]; then
        log_error "Invalid suffix number: $suffix_num"
        log_error "Suffix number should be a positive integer"
        exit 1
    fi

    # Run repack
    if repack_deb "$deb_file" "$distro" "$suffix_num" "$output_dir"; then
        exit 0
    else
        log_error "Repack failed"
        exit 1
    fi
}

# Run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
