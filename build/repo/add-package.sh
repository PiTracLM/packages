#!/bin/bash
# Add package to repository
# Usage: ./add-package.sh <package.deb> [distribution] [component]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package.deb> [distribution] [component]"
    echo "  distribution: bookworm (default) or trixie"
    echo "  component: main (default), contrib, or non-free"
    exit 1
fi

PACKAGE="$1"
DISTRO="${2:-bookworm}"
COMPONENT="${3:-main}"

if [ ! -f "$PACKAGE" ]; then
    echo "Error: Package file not found: $PACKAGE"
    exit 1
fi

if [[ "$DISTRO" != "bookworm" && "$DISTRO" != "trixie" ]]; then
    echo "Error: Distribution must be 'bookworm' or 'trixie'"
    exit 1
fi

echo "Adding package: $PACKAGE to $DISTRO (component: $COMPONENT)"

# Include the package
reprepro includedeb "$DISTRO" "$PACKAGE"

echo "Package added successfully to $DISTRO"
