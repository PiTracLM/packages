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

log_info() { echo -e "${BLUE}[INFO]$(NC) $*"; }
log_warn() { echo -e "${YELLOW}[WARN]$(NC) $*"; }
log_error() { echo -e "${RED}[ERROR]$(NC) $*" >&2; }
log_success() { echo -e "${GREEN}[✓]$(NC) $*"; }

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
    local package_name
    local component

    package_name=$(dpkg-deb -f "$deb_file" Package)
    component=$(get_component "$package_name")

    log_info "Adding $package_name ($(basename "$deb_file")) to component $component"

    cd "$REPO_DIR"

    if reprepro list bookworm | grep -q "^bookworm|$component|.*: $package_name "; then
        log_info "Removing existing version of $package_name"
        reprepro remove bookworm "$package_name" || true
    fi

    if reprepro includedeb bookworm "$deb_file"; then
        log_success "Added $package_name successfully"
    else
        log_error "Failed to add $package_name"
        return 1
    fi
}

process_packages_in_order() {
    local -a package_order=(
        "liblgpio1"
        "liblgpio-dev"
        "libmsgpack-cxx-dev"
        "libopencv4.11"
        "libopencv-dev"
        "pitrac"
        "pitrac-dev"
    )

    local -A available_packages

    while IFS= read -r -d '' deb_file; do
        local package_name
        package_name=$(dpkg-deb -f "$deb_file" Package)
        available_packages["$package_name"]="$deb_file"
    done < <(find "$DEBS_DIR" -name "*.deb" -type f -print0)

    log_info "Found ${#available_packages[@]} packages to process"

    local processed_count=0
    for package in "${package_order[@]}"; do
        if [ -n "${available_packages[$package]:-}" ]; then
            if add_package_to_repo "${available_packages[$package]}"; then
                ((processed_count++))
                unset available_packages["$package"]
            fi
        fi
    done

    for package in "${!available_packages[@]}"; do
        if add_package_to_repo "${available_packages[$package]}"; then
            ((processed_count++))
        fi
    done

    log_info "Processed $processed_count packages total"
}

update_repository_metadata() {
    log_info "Updating repository metadata..."

    cd "$REPO_DIR"

    if reprepro export bookworm; then
        log_success "Repository metadata updated"
    else
        log_error "Failed to update repository metadata"
        return 1
    fi

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

    local main_count
    local contrib_count
    local nonfree_count

    main_count=$(reprepro list bookworm | grep "|main|" | wc -l)
    contrib_count=$(reprepro list bookworm | grep "|contrib|" | wc -l)
    nonfree_count=$(reprepro list bookworm | grep "|non-free|" | wc -l)

    echo "  Main: $main_count packages"
    echo "  Contrib: $contrib_count packages"
    echo "  Non-free: $nonfree_count packages"
    echo ""

    echo "By Architecture:"
    reprepro list bookworm | cut -d'|' -f4 | sort | uniq -c | while read count arch; do
        echo "  $arch: $count packages"
    done
    echo ""

    echo "Packages:"
    reprepro listmatched bookworm '*' | while IFS='|' read dist component arch package rest; do
        echo "  $package ($arch)"
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
    log_info "Updating APT repository"
    log_info "Repository: $REPO_DIR"
    log_info "Packages: $DEBS_DIR"
    echo ""

    local deb_count
    deb_count=$(find "$DEBS_DIR" -name "*.deb" -type f | wc -l)

    if [ "$deb_count" -eq 0 ]; then
        log_warn "No .deb files found in $DEBS_DIR"
        exit 0
    fi

    log_info "Found $deb_count .deb files to process"

    if ! process_packages_in_order; then
        log_error "Failed to process packages"
        exit 1
    fi

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
    log_info "Repository updated successfully!"
    echo ""
    log_info "To use this repository, add it to your APT sources:"
    echo "  echo 'deb [arch=arm64] https://your-domain.com/repo bookworm main' | sudo tee /etc/apt/sources.list.d/pitrac.list"

    if [ -f "$REPO_DIR/public.key" ]; then
        echo ""
        log_info "Add the GPG key:"
        echo "  curl -fsSL https://your-domain.com/repo/public.key | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg"
        echo ""
        log_info "Update the sources list to use the key:"
        echo "  echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/pitrac-archive-keyring.gpg] https://your-domain.com/repo bookworm main' | sudo tee /etc/apt/sources.list.d/pitrac.list"
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