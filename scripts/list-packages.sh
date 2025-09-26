#!/bin/bash
# list-packages.sh - Script to list packages in the PiTrac APT repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose     Show detailed package information"
    echo "  -c, --component   Filter by component (main, contrib, non-free)"
    echo "  -a, --arch        Filter by architecture (arm64)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # List all packages"
    echo "  $0 --verbose                 # List with details"
    echo "  $0 --component main          # List only main component"
    echo "  $0 --arch arm64             # List only arm64 packages"
    exit 1
}

VERBOSE=false
COMPONENT=""
ARCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--component)
            COMPONENT="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -n "$COMPONENT" ] && [[ ! "$COMPONENT" =~ ^(main|contrib|non-free)$ ]]; then
    echo "Error: Component must be 'main', 'contrib', or 'non-free'"
    exit 1
fi

if [ -n "$ARCH" ] && [[ ! "$ARCH" =~ ^(arm64|all)$ ]]; then
    echo "Error: Architecture must be 'arm64' or 'all' (PiTrac packages are arm64-only for Raspberry Pi 5)"
    exit 1
fi

cd "$REPO_ROOT"

echo "PiTrac APT Repository - Package List"
echo "===================================="

if [ "$VERBOSE" = true ]; then
    PACKAGES=$(reprepro list bookworm)
    if [ -z "$PACKAGES" ]; then
        echo "No packages found in repository."
        exit 0
    fi

    echo "$PACKAGES" | while IFS='|' read -r suite component arch package_info; do
        suite=$(echo "$suite" | xargs)
        component=$(echo "$component" | xargs)
        arch=$(echo "$arch" | xargs)
        package_info=$(echo "$package_info" | xargs)

        if [ -n "$COMPONENT" ] && [ "$component" != "$COMPONENT" ]; then
            continue
        fi
        if [ -n "$ARCH" ] && [ "$arch" != "$ARCH" ]; then
            continue
        fi

        package_name=$(echo "$package_info" | cut -d' ' -f1)
        version=$(echo "$package_info" | cut -d' ' -f2)

        printf "%-20s %-15s %-8s %-8s\n" "$package_name" "$version" "$arch" "$component"
    done
else
    PACKAGES=$(reprepro list bookworm | cut -d'|' -f4 | cut -d' ' -f1 | sort -u)
    if [ -z "$PACKAGES" ]; then
        echo "No packages found in repository."
        exit 0
    fi

    echo "Package Names:"
    echo "--------------"
    echo "$PACKAGES"
fi

echo ""
echo "Total packages: $(reprepro list bookworm | wc -l)"