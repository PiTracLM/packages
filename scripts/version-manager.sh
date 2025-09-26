#!/usr/bin/env bash
# Version management script for PiTrac packages
# Handles automatic versioning, tagging, and changelog generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]$(NC) $*"; }
log_warn() { echo -e "${YELLOW}[WARN]$(NC) $*"; }
log_error() { echo -e "${RED}[ERROR]$(NC) $*" >&2; }
log_success() { echo -e "${GREEN}[✓]$(NC) $*"; }

VERSION_FILE="$PROJECT_ROOT/VERSION"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

declare -A BASE_VERSIONS=(
    ["lgpio"]="0.2.2"
    ["msgpack"]="6.1.1"
    ["opencv"]="4.11.0"
    ["pitrac"]="1.0.0"
)

load_versions() {
    if [ -f "$VERSION_FILE" ]; then
        source "$VERSION_FILE"
    else
        for package in "${!BASE_VERSIONS[@]}"; do
            declare -g "${package^^}_VERSION"="${BASE_VERSIONS[$package]}-1"
        done
    fi
}

save_versions() {
    cat > "$VERSION_FILE" << EOF
# PiTrac Package Versions
# Generated on $(date)

LGPIO_VERSION="${LGPIO_VERSION}"
MSGPACK_VERSION="${MSGPACK_VERSION}"
OPENCV_VERSION="${OPENCV_VERSION}"
PITRAC_VERSION="${PITRAC_VERSION}"

# Base versions (upstream)
LGPIO_BASE="${BASE_VERSIONS[lgpio]}"
MSGPACK_BASE="${BASE_VERSIONS[msgpack]}"
OPENCV_BASE="${BASE_VERSIONS[opencv]}"
PITRAC_BASE="${BASE_VERSIONS[pitrac]}"
EOF
}

parse_version() {
    local version="$1"
    local base_version="${version%-*}"
    local revision="${version##*-}"
    echo "$base_version" "$revision"
}

increment_version() {
    local package="$1"
    local increment_type="${2:-patch}"

    local var_name="${package^^}_VERSION"
    local current_version="${!var_name}"

    read -r base_version revision <<< "$(parse_version "$current_version")"

    case "$increment_type" in
        major)
            IFS='.' read -ra version_parts <<< "$base_version"
            version_parts[0]=$((version_parts[0] + 1))
            version_parts[1]=0
            version_parts[2]=0
            base_version="${version_parts[0]}.${version_parts[1]}.${version_parts[2]}"
            revision=1
            ;;
        minor)
            IFS='.' read -ra version_parts <<< "$base_version"
            version_parts[1]=$((version_parts[1] + 1))
            version_parts[2]=0
            base_version="${version_parts[0]}.${version_parts[1]}.${version_parts[2]}"
            revision=1
            ;;
        patch)
            IFS='.' read -ra version_parts <<< "$base_version"
            version_parts[2]=$((version_parts[2] + 1))
            base_version="${version_parts[0]}.${version_parts[1]}.${version_parts[2]}"
            revision=1
            ;;
        revision)
            revision=$((revision + 1))
            ;;
        *)
            log_error "Unknown increment type: $increment_type"
            return 1
            ;;
    esac

    local new_version="${base_version}-${revision}"
    declare -g "$var_name"="$new_version"

    log_info "Incremented $package version: $current_version -> $new_version"
}

set_version() {
    local package="$1"
    local version="$2"

    local var_name="${package^^}_VERSION"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]; then
        log_error "Invalid version format: $version (expected: x.y.z-r)"
        return 1
    fi

    declare -g "$var_name"="$version"
    log_info "Set $package version to: $version"
}

auto_version() {
    local package="$1"
    local base_version="${BASE_VERSIONS[$package]}"

    local date_version=$(date +%Y.%m.%d)
    local git_count=""

    if git rev-parse --git-dir > /dev/null 2>&1; then
        git_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    else
        git_count="0"
    fi

    if [ "$package" = "pitrac" ]; then
        local auto_version="${date_version}-${git_count}"
    else
        local var_name="${package^^}_VERSION"
        local current_version="${!var_name}"
        read -r base_version revision <<< "$(parse_version "$current_version")"
        revision=$((revision + 1))
        auto_version="${base_version}-${revision}"
    fi

    local var_name="${package^^}_VERSION"
    declare -g "$var_name"="$auto_version"

    log_info "Auto-generated $package version: $auto_version"
}

add_changelog_entry() {
    local package="$1"
    local version="$2"
    local message="${3:-Automated build}"

    if [ ! -f "$CHANGELOG_FILE" ]; then
        cat > "$CHANGELOG_FILE" << 'EOF'
# PiTrac Packages Changelog

All notable changes to PiTrac packages will be documented in this file.

EOF
    fi

    local temp_file=$(mktemp)

    cat > "$temp_file" << EOF
## [$package $version] - $(date +%Y-%m-%d)

### Changed
- $message

EOF

    cat "$CHANGELOG_FILE" >> "$temp_file"

    mv "$temp_file" "$CHANGELOG_FILE"

    log_info "Added changelog entry for $package $version"
}

create_git_tag() {
    local package="$1"
    local version="$2"
    local message="${3:-Release $package $version}"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warn "Not in a git repository, skipping tag creation"
        return 0
    fi

    local tag="${package}-v${version}"

    if git tag -l | grep -q "^${tag}$"; then
        log_warn "Tag $tag already exists"
        return 0
    fi

    if git tag -a "$tag" -m "$message"; then
        log_success "Created git tag: $tag"
    else
        log_error "Failed to create git tag: $tag"
        return 1
    fi
}

show_versions() {
    echo "Current PiTrac Package Versions:"
    echo "================================"
    echo ""
    for package in lgpio msgpack opencv pitrac; do
        local var_name="${package^^}_VERSION"
        local version="${!var_name}"
        printf "  %-10s %s\n" "$package:" "$version"
    done
    echo ""

    if [ -f "$VERSION_FILE" ]; then
        echo "Version file: $VERSION_FILE"
        echo "Last updated: $(stat -c %y "$VERSION_FILE" 2>/dev/null || echo "unknown")"
    else
        echo "Version file: Not created yet"
    fi
}

release_package() {
    local package="$1"
    local increment_type="${2:-revision}"
    local message="${3:-}"

    log_info "Releasing $package ($increment_type increment)"

    increment_version "$package" "$increment_type"

    local var_name="${package^^}_VERSION"
    local new_version="${!var_name}"

    save_versions

    if [ -n "$message" ]; then
        add_changelog_entry "$package" "$new_version" "$message"
    else
        add_changelog_entry "$package" "$new_version" "Release $package $new_version"
    fi

    create_git_tag "$package" "$new_version" "Release $package $new_version"

    log_success "Released $package $new_version"
}

show_usage() {
    cat << 'EOF'
PiTrac Version Manager

Usage: ./version-manager.sh [command] [options]

Commands:
  show                          Show current package versions
  increment <package> [type]    Increment package version
  set <package> <version>       Set specific package version
  auto <package>               Generate automatic version
  release <package> [type] [message]  Full release (increment, changelog, tag)
  save                         Save current versions to file
  reload                       Reload versions from file

Increment types:
  major                        Increment major version (x.0.0-1)
  minor                        Increment minor version (x.y.0-1)
  patch                        Increment patch version (x.y.z-1)
  revision                     Increment revision (x.y.z-r) [default]

Packages: lgpio, msgpack, opencv, pitrac

Examples:
  ./version-manager.sh show
  ./version-manager.sh increment pitrac
  ./version-manager.sh increment opencv minor
  ./version-manager.sh set pitrac 1.2.3-4
  ./version-manager.sh auto pitrac
  ./version-manager.sh release pitrac revision "Bug fixes"

EOF
}

main() {
    load_versions

    local command="${1:-show}"

    case "$command" in
        show)
            show_versions
            ;;
        increment)
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                echo ""
                show_usage
                exit 1
            fi
            local package="$2"
            local increment_type="${3:-revision}"
            increment_version "$package" "$increment_type"
            save_versions
            ;;
        set)
            if [ $# -lt 3 ]; then
                log_error "Package name and version required"
                echo ""
                show_usage
                exit 1
            fi
            local package="$2"
            local version="$3"
            set_version "$package" "$version"
            save_versions
            ;;
        auto)
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                echo ""
                show_usage
                exit 1
            fi
            local package="$2"
            auto_version "$package"
            save_versions
            ;;
        release)
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                echo ""
                show_usage
                exit 1
            fi
            local package="$2"
            local increment_type="${3:-revision}"
            local message="${4:-}"
            release_package "$package" "$increment_type" "$message"
            ;;
        save)
            save_versions
            log_success "Versions saved to $VERSION_FILE"
            ;;
        reload)
            load_versions
            log_success "Versions reloaded from $VERSION_FILE"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"