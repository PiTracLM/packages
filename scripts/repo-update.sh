#!/usr/bin/env bash
# Update APT repository with built packages
# Usage: ./repo-update.sh <repo_dir> <debs_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

if [ $# -ne 2 ]; then
    log_error "Usage: $0 <repo_dir> <debs_dir>"
    exit 1
fi

REPO_DIR="$1"
DEBS_DIR="$2"

if [ ! -d "$REPO_DIR" ]; then
    log_error "Repository directory not found: $REPO_DIR"
    log_info "Initialize repository first with: ./repo-init.sh $REPO_DIR"
    exit 1
fi

if [ ! -d "$DEBS_DIR" ]; then
    log_error "DEBs directory not found: $DEBS_DIR"
    exit 1
fi

if [ ! -f "$REPO_DIR/conf/distributions" ]; then
    log_error "Repository not properly initialized: $REPO_DIR/conf/distributions missing"
    exit 1
fi

if ! command -v reprepro &> /dev/null; then
    log_error "reprepro is not installed"
    exit 1
fi

get_component() {
    local package_name="$1"

    case "$package_name" in
        *-dev|*-dbg)
            echo "main"
            ;;
        pitrac)
            echo "main"
            ;;
        lib*)
            echo "main"
            ;;
        *)
            echo "main"
            ;;
    esac
}

add_package_to_repo() {
    local deb_file="$1"
    local distro="$2"
    local package_name
    local component

    package_name=$(dpkg-deb -f "$deb_file" Package)
    component=$(get_component "$package_name")

    log_info "Adding $package_name ($(basename "$deb_file")) to $distro/$component"

    cd "$REPO_DIR"

    if reprepro list "$distro" | grep -q "^$distro|$component|.*: $package_name "; then
        log_info "Removing existing version of $package_name from $distro"
        reprepro remove "$distro" "$package_name" || true
    fi

    if reprepro includedeb "$distro" "$deb_file"; then
        log_success "Added $package_name to $distro successfully"
    else
        log_error "Failed to add $package_name to $distro"
        return 1
    fi
}

process_packages_in_order() {
    local distro="$1"
    local distro_debs_dir="$DEBS_DIR/$distro/arm64"

    local -a package_order=(
        "liblgpio1"
        "liblgpio-dev"
        "libmsgpack-cxx-dev"
        "libactivemq-cpp"
        "libactivemq-cpp-dev"
        "libopencv4.11"
        "libopencv-dev"
        "libonnxruntime1.17.3"
        "libonnxruntime1.22.1"
        "pitrac"
        "pitrac-dev"
    )

    if [ ! -d "$distro_debs_dir" ]; then
        log_warn "No packages found for $distro at $distro_debs_dir"
        return 0
    fi

    local -A available_packages

    while IFS= read -r -d '' deb_file; do
        local package_name
        package_name=$(dpkg-deb -f "$deb_file" Package)
        available_packages["$package_name"]="$deb_file"
    done < <(find "$distro_debs_dir" -name "*.deb" -type f -print0)

    log_info "Found ${#available_packages[@]} packages to process for $distro"

    local processed_count=0
    for package in "${package_order[@]}"; do
        if [ -n "${available_packages[$package]:-}" ]; then
            if add_package_to_repo "${available_packages[$package]}" "$distro"; then
                ((processed_count++))
                unset available_packages["$package"]
            fi
        fi
    done

    for package in "${!available_packages[@]}"; do
        if add_package_to_repo "${available_packages[$package]}" "$distro"; then
            ((processed_count++))
        fi
    done

    log_info "Processed $processed_count packages total for $distro"
}

update_repository_metadata() {
    log_info "Updating repository metadata for all distributions..."

    cd "$REPO_DIR"

    for distro in bookworm trixie; do
        if reprepro export "$distro"; then
            log_success "Repository metadata updated for $distro"
        else
            log_error "Failed to update repository metadata for $distro"
            return 1
        fi
    done

    if reprepro deleteunreferenced; then
        log_info "Cleaned up unreferenced files"
    else
        log_warn "Failed to clean up unreferenced files"
    fi
}

generate_statistics() {
    log_info "Repository Statistics:"
    echo "===================="

    cd "$REPO_DIR"

    for distro in bookworm trixie; do
        echo ""
        echo "$distro (Debian $([ "$distro" = "bookworm" ] && echo "12" || echo "13")):"
        echo "-------------------"

        local main_count
        local contrib_count
        local nonfree_count

        main_count=$(reprepro list "$distro" | grep "|main|" | wc -l)
        contrib_count=$(reprepro list "$distro" | grep "|contrib|" | wc -l)
        nonfree_count=$(reprepro list "$distro" | grep "|non-free|" | wc -l)

        echo "  Main: $main_count packages"
        echo "  Contrib: $contrib_count packages"
        echo "  Non-free: $nonfree_count packages"
        echo ""

        echo "  Packages:"
        reprepro listmatched "$distro" '*' | while IFS='|' read dist component arch package rest; do
            echo "    $package ($arch)"
        done
    done
}

verify_repository() {
    log_info "Verifying repository integrity..."

    cd "$REPO_DIR"

    if reprepro check; then
        log_success "Repository integrity check passed"
    else
        log_error "Repository integrity check failed"
        return 1
    fi
}

main() {
    log_info "Updating APT repository for all distributions"
    log_info "Repository: $REPO_DIR"
    log_info "Packages: $DEBS_DIR"
    echo ""

    local deb_count
    deb_count=$(find "$DEBS_DIR" -name "*.deb" -type f | wc -l)

    if [ "$deb_count" -eq 0 ]; then
        log_warn "No .deb files found in $DEBS_DIR"
        exit 0
    fi

    log_info "Found $deb_count .deb files total to process"
    echo ""

    # Process packages for each distribution
    for distro in bookworm trixie; do
        log_info "Processing packages for $distro..."
        if ! process_packages_in_order "$distro"; then
            log_error "Failed to process packages for $distro"
            exit 1
        fi
        echo ""
    done

    if ! update_repository_metadata; then
        log_error "Failed to update repository metadata"
        exit 1
    fi

    if ! verify_repository; then
        log_error "Repository verification failed"
        exit 1
    fi

    echo ""
    generate_statistics

    echo ""
    log_success "Repository updated successfully for all distributions!"
    echo ""
    log_info "To use this repository on Debian 12 (Bookworm):"
    echo "  echo 'deb [arch=arm64] https://your-domain.com/repo bookworm main' | sudo tee /etc/apt/sources.list.d/pitrac.list"
    echo ""
    log_info "To use this repository on Debian 13 (Trixie):"
    echo "  echo 'deb [arch=arm64] https://your-domain.com/repo trixie main' | sudo tee /etc/apt/sources.list.d/pitrac.list"

    if [ -f "$REPO_DIR/public.key" ]; then
        echo ""
        log_info "Add the GPG key (same for both distros):"
        echo "  curl -fsSL https://your-domain.com/repo/public.key | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg"
        echo ""
        log_info "Then update the sources list to use the key (for your distro):"
        echo "  Bookworm: echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/pitrac-archive-keyring.gpg] https://your-domain.com/repo bookworm main' | sudo tee /etc/apt/sources.list.d/pitrac.list"
        echo "  Trixie:   echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/pitrac-archive-keyring.gpg] https://your-domain.com/repo trixie main' | sudo tee /etc/apt/sources.list.d/pitrac.list"
    fi

    echo ""
    log_info "Then update and install:"
    echo "  sudo apt update"
    echo "  sudo apt install pitrac"
}

if [ "${1:-}" = "--dry-run" ]; then
    log_info "DRY RUN MODE - No changes will be made"
    shift
fi

main "$@"