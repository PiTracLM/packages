#!/usr/bin/env bash
# Test built packages for basic integrity and dependencies
# Usage: ./test-packages.sh <debs_dir>

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

if [ $# -ne 1 ]; then
    log_error "Usage: $0 <debs_dir>"
    exit 1
fi

DEBS_DIR="$1"

if [ ! -d "$DEBS_DIR" ]; then
    log_error "DEBs directory not found: $DEBS_DIR"
    exit 1
fi

validate_package_format() {
    local deb_file="$1"

    log_info "Validating format: $(basename "$deb_file")"

    if ! dpkg-deb -I "$deb_file" >/dev/null 2>&1; then
        log_error "Invalid .deb format: $deb_file"
        return 1
    fi

    local package_name
    local version
    local architecture

    package_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || echo "")
    version=$(dpkg-deb -f "$deb_file" Version 2>/dev/null || echo "")
    architecture=$(dpkg-deb -f "$deb_file" Architecture 2>/dev/null || echo "")

    if [ -z "$package_name" ] || [ -z "$version" ] || [ -z "$architecture" ]; then
        log_error "Missing required metadata in: $deb_file"
        return 1
    fi

    log_success "Valid package: $package_name $version ($architecture)"
    return 0
}

validate_package_contents() {
    local deb_file="$1"

    log_info "Validating contents: $(basename "$deb_file")"

    local contents
    contents=$(dpkg-deb -c "$deb_file" 2>/dev/null || echo "")

    if [ -z "$contents" ]; then
        log_error "Cannot list package contents: $deb_file"
        return 1
    fi

    if echo "$contents" | grep -q "\.\./"; then
        log_error "Package contains dangerous paths (../): $deb_file"
        return 1
    fi

    local file_count
    file_count=$(echo "$contents" | wc -l)

    if [ "$file_count" -eq 0 ]; then
        log_warn "Package appears to be empty: $deb_file"
        return 1
    fi

    log_success "Package contains $file_count files/directories"
    return 0
}

check_dependencies() {
    local deb_file="$1"

    log_info "Checking dependencies: $(basename "$deb_file")"

    local depends
    depends=$(dpkg-deb -f "$deb_file" Depends 2>/dev/null || echo "")

    if [ -n "$depends" ]; then
        log_info "Dependencies: $depends"

        if echo "$depends" | grep -qE '[<>]=?[^,]*,'; then
            log_error "Malformed dependency in: $deb_file"
            return 1
        fi
    else
        log_info "No dependencies declared"
    fi

    return 0
}

test_package_installation() {
    local deb_file="$1"
    local package_name

    package_name=$(dpkg-deb -f "$deb_file" Package")

    log_info "Testing installation simulation: $package_name"

    # Create temporary directory for testing
    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract package to temporary location
    if dpkg-deb -x "$deb_file" "$temp_dir" 2>/dev/null; then
        log_success "Package extracts successfully"

        # Check for common file issues
        if find "$temp_dir" -type f -perm /u+s | grep -q .; then
            log_warn "Package contains setuid files (security review recommended)"
        fi

        if find "$temp_dir" -type f -name "*.so*" | grep -q .; then
            log_info "Package contains shared libraries"
        fi

        if find "$temp_dir" -path "*/bin/*" -type f | grep -q .; then
            log_info "Package contains executable binaries"
        fi

    else
        log_error "Failed to extract package: $deb_file"
        rm -rf "$temp_dir"
        return 1
    fi

    # Cleanup
    rm -rf "$temp_dir"
    return 0
}

check_package_size() {
    local deb_file="$1"

    local size_bytes
    size_bytes=$(stat -c%s "$deb_file" 2>/dev/null || echo "0")

    if [ "$size_bytes" -eq 0 ]; then
        log_error "Package file is empty: $deb_file"
        return 1
    fi

    # Convert to human readable
    local size_human
    if command -v numfmt >/dev/null 2>&1; then
        size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes")
    else
        size_human="${size_bytes} bytes"
    fi

    log_info "Package size: $size_human"

    # Warn about very large packages (>100MB)
    if [ "$size_bytes" -gt 104857600 ]; then
        log_warn "Large package size: $size_human"
    fi

    return 0
}

# Main testing function
test_single_package() {
    local deb_file="$1"
    local errors=0

    echo ""
    log_info "Testing package: $(basename "$deb_file")"
    echo "================================="

    validate_package_format "$deb_file" || ((errors++))
    validate_package_contents "$deb_file" || ((errors++))
    check_dependencies "$deb_file" || ((errors++))
    check_package_size "$deb_file" || ((errors++))
    test_package_installation "$deb_file" || ((errors++))

    if [ "$errors" -eq 0 ]; then
        log_success "Package passed all tests: $(basename "$deb_file")"
    else
        log_error "Package failed $errors tests: $(basename "$deb_file")"
    fi

    return "$errors"
}

# Test dependency relationships
test_dependency_tree() {
    log_info "Testing package dependency relationships..."

    local -A packages
    local -A package_deps

    # Collect all packages and their dependencies
    while IFS= read -r -d '' deb_file; do
        local pkg_name
        local deps

        pkg_name=$(dpkg-deb -f "$deb_file" Package)
        deps=$(dpkg-deb -f "$deb_file" Depends 2>/dev/null || echo "")

        packages["$pkg_name"]="$deb_file"
        package_deps["$pkg_name"]="$deps"

    done < <(find "$DEBS_DIR" -name "*.deb" -type f -print0)

    # Check for circular dependencies (basic check)
    for pkg in "${!packages[@]}"; do
        local deps="${package_deps[$pkg]}"
        if echo "$deps" | grep -q "$pkg"; then
            log_warn "Potential self-dependency in $pkg: $deps"
        fi
    done

    log_success "Dependency tree analysis complete"
}

# Main execution
main() {
    log_info "PiTrac Package Testing Suite"
    log_info "Testing packages in: $DEBS_DIR"
    echo ""

    # Find all .deb files
    local deb_files=()
    while IFS= read -r -d '' file; do
        deb_files+=("$file")
    done < <(find "$DEBS_DIR" -name "*.deb" -type f -print0)

    if [ ${#deb_files[@]} -eq 0 ]; then
        log_warn "No .deb files found in $DEBS_DIR"
        exit 0
    fi

    log_info "Found ${#deb_files[@]} packages to test"

    # Test each package
    local total_errors=0
    local tested_packages=0

    for deb_file in "${deb_files[@]}"; do
        if test_single_package "$deb_file"; then
            ((tested_packages++))
        else
            ((total_errors++))
            ((tested_packages++))
        fi
    done

    # Test dependency relationships
    echo ""
    test_dependency_tree

    # Summary
    echo ""
    log_info "Testing Summary"
    echo "==============="
    echo "Packages tested: $tested_packages"
    echo "Packages passed: $((tested_packages - total_errors))"
    echo "Packages failed: $total_errors"

    if [ "$total_errors" -eq 0 ]; then
        log_success "All packages passed testing!"
        exit 0
    else
        log_error "$total_errors packages failed testing"
        exit 1
    fi
}

# Show usage if requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat << 'EOF'
PiTrac Package Testing Suite

Usage: ./test-packages.sh <debs_dir>

Tests:
  - Package format validation
  - Content structure verification
  - Dependency checking
  - Installation simulation
  - Size validation
  - Dependency tree analysis

Examples:
  ./test-packages.sh build/debs
  ./test-packages.sh /path/to/packages

EOF
    exit 0
fi

# Run main function
main "$@"