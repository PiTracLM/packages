#!/bin/bash
# add-package.sh - Script to add packages to the PiTrac APT repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 <package.deb> [component]"
    echo ""
    echo "Arguments:"
    echo "  package.deb    Path to the .deb package file"
    echo "  component      Repository component (main, contrib, non-free). Default: main"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/package_1.0.0_arm64.deb"
    echo "  $0 /path/to/package_1.0.0_arm64.deb contrib"
    exit 1
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

PACKAGE_FILE="$1"
COMPONENT="${2:-main}"

if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Error: Package file '$PACKAGE_FILE' does not exist"
    exit 1
fi

if [[ ! "$COMPONENT" =~ ^(main|contrib|non-free)$ ]]; then
    echo "Error: Component must be 'main', 'contrib', or 'non-free'"
    exit 1
fi

PACKAGE_NAME=$(dpkg-deb -f "$PACKAGE_FILE" Package)
VERSION=$(dpkg-deb -f "$PACKAGE_FILE" Version)
ARCHITECTURE=$(dpkg-deb -f "$PACKAGE_FILE" Architecture)

echo "Adding package: $PACKAGE_NAME v$VERSION ($ARCHITECTURE) to $COMPONENT"

cd "$REPO_ROOT"

INCOMING_FILE="incoming/$(basename "$PACKAGE_FILE")"
cp "$PACKAGE_FILE" "$INCOMING_FILE"

if [ "$COMPONENT" = "main" ]; then
    reprepro -V includedeb bookworm "$INCOMING_FILE"
else
    reprepro -V --section "$COMPONENT" --component "$COMPONENT" includedeb bookworm "$INCOMING_FILE"
fi

rm "$INCOMING_FILE"

echo "Successfully added $PACKAGE_NAME v$VERSION to $COMPONENT component"
echo "Repository updated. Don't forget to commit and push changes to GitHub."