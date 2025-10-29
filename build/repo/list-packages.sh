#!/bin/bash
# List packages in repository
# Usage: ./list-packages.sh [distribution] [--verbose]

DISTRO="${1:-all}"
VERBOSE=""

if [[ "$1" == "--verbose" || "$2" == "--verbose" ]]; then
    VERBOSE="--verbose"
    if [[ "$1" == "--verbose" ]]; then
        DISTRO="all"
    fi
fi

if [[ "$DISTRO" != "bookworm" && "$DISTRO" != "trixie" && "$DISTRO" != "all" ]]; then
    echo "Usage: $0 [distribution] [--verbose]"
    echo "  distribution: bookworm, trixie, or all (default)"
    exit 1
fi

list_distro() {
    local dist=$1
    echo ""
    echo "=== $dist ==="
    if [ -n "$VERBOSE" ]; then
        echo "Detailed package listing:"
        reprepro list "$dist"
    else
        echo "Package summary:"
        reprepro listmatched "$dist" '*' | cut -d' ' -f2 | sort | uniq -c
    fi
}

if [[ "$DISTRO" == "all" ]]; then
    list_distro bookworm
    list_distro trixie
else
    list_distro "$DISTRO"
fi
