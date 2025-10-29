#!/bin/bash
# Remove package from repository
# Usage: ./remove-package.sh <package-name> [distribution]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-name> [distribution]"
    echo "  distribution: bookworm (default), trixie, or 'all' for both"
    exit 1
fi

PACKAGE="$1"
DISTRO="${2:-bookworm}"

if [[ "$DISTRO" == "all" ]]; then
    echo "Removing package: $PACKAGE from all distributions"
    reprepro remove bookworm "$PACKAGE" || true
    reprepro remove trixie "$PACKAGE" || true
    echo "Package removed from all distributions"
elif [[ "$DISTRO" != "bookworm" && "$DISTRO" != "trixie" ]]; then
    echo "Error: Distribution must be 'bookworm', 'trixie', or 'all'"
    exit 1
else
    echo "Removing package: $PACKAGE from $DISTRO"
    reprepro remove "$DISTRO" "$PACKAGE"
    echo "Package removed successfully from $DISTRO"
fi
