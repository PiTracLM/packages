#!/bin/bash
# remove-package.sh - Script to remove packages from the PiTrac APT repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 <package-name>"
    echo ""
    echo "Arguments:"
    echo "  package-name   Name of the package to remove"
    echo ""
    echo "Examples:"
    echo "  $0 pitrac"
    echo "  $0 opencv-dev"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

PACKAGE_NAME="$1"

echo "Removing package: $PACKAGE_NAME"

cd "$REPO_ROOT"

echo "Current packages in repository:"
reprepro list bookworm | grep "^bookworm|" || true

if reprepro list bookworm | grep -q ": $PACKAGE_NAME "; then
    reprepro remove bookworm "$PACKAGE_NAME"
    echo "Successfully removed $PACKAGE_NAME from repository"
    echo "Repository updated. Don't forget to commit and push changes to GitHub."
else
    echo "Warning: Package $PACKAGE_NAME not found in repository"
    exit 1
fi