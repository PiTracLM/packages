#!/usr/bin/env bash
# Initialize APT repository with reprepro
# Usage: ./repo-init.sh <repo_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]$(NC) $*"; }
log_warn() { echo -e "${YELLOW}[WARN]$(NC) $*"; }
log_error() { echo -e "${RED}[ERROR]$(NC) $*" >&2; }
log_success() { echo -e "${GREEN}[✓]$(NC) $*"; }

# Validate arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 <repo_dir>"
    exit 1
fi

REPO_DIR="$1"

# Check if reprepro is installed
if ! command -v reprepro &> /dev/null; then
    log_error "reprepro is not installed. Please install it first:"
    log_error "  sudo apt-get install reprepro"
    exit 1
fi

# Create repository directory structure
log_info "Creating repository directory structure in $REPO_DIR"
mkdir -p "$REPO_DIR"/{conf,dists,pool,incoming,tmp}

# Create reprepro configuration
log_info "Creating reprepro configuration..."

# GPG key setup
GPG_KEY_ID=""
if command -v gpg &> /dev/null; then
    # Check if we have a GPG key
    if gpg --list-secret-keys | grep -q "sec"; then
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG | grep "sec" | head -1 | sed 's/.*\/\([A-F0-9]\{16\}\).*/\1/')
        log_info "Found GPG key: $GPG_KEY_ID"
    else
        log_warn "No GPG key found. Repository will be unsigned."
        log_info "To create a GPG key for signing packages:"
        log_info "  gpg --full-generate-key"
        log_info "  # Choose RSA, 4096 bits, no expiration"
        log_info "  # Use 'PiTrac Build System <build@pitrac.org>' as identity"
    fi
fi

# Create distributions file
cat > "$REPO_DIR/conf/distributions" << EOF
Origin: PiTrac
Label: PiTrac Packages
Codename: bookworm
Architectures: arm64 source
Components: main contrib non-free
Description: PiTrac package repository for Debian/Raspbian Bookworm
EOF

# Add SignWith if we have a GPG key
if [ -n "$GPG_KEY_ID" ]; then
    echo "SignWith: $GPG_KEY_ID" >> "$REPO_DIR/conf/distributions"
fi

# Create options file
cat > "$REPO_DIR/conf/options" << 'EOF'
# Global reprepro options
verbose
ask-passphrase
basedir .
EOF

# Create incoming configuration for automated uploads
cat > "$REPO_DIR/conf/incoming" << 'EOF'
Name: default
IncomingDir: incoming
TempDir: tmp
Allow: bookworm
Cleanup: unused_files on_deny on_error
EOF

mkdir -p "$REPO_DIR/conf/override"

cat > "$REPO_DIR/conf/override.bookworm.main" << 'EOF'
# Override file for main component
# Format: package priority section [maintainer]

# PiTrac packages
pitrac optional misc
pitrac-dev optional libdevel

# Library packages
liblgpio1 optional libs
liblgpio-dev optional libdevel
libmsgpack-cxx-dev optional libdevel
libopencv4.11 optional libs
libopencv-dev optional libdevel
EOF

cat > "$REPO_DIR/conf/updates" << 'EOF'
# Updates configuration for external sources
# Currently empty - all packages are built locally
EOF

cat > "$REPO_DIR/conf/pulls" << 'EOF'
# Pull configuration for copying packages between distributions
# Currently empty
EOF

log_info "Initializing repository..."
cd "$REPO_DIR"

if ! reprepro export bookworm; then
    log_error "Failed to initialize repository"
    exit 1
fi

cat > "$REPO_DIR/.htaccess" << 'EOF'
Options +Indexes
IndexOptions FancyIndexing HTMLTable NameWidth=* DescriptionWidth=*
HeaderName /header.html
ReadmeName /footer.html

# Compress text files
<Files "*.txt">
    <IfModule mod_deflate.c>
        SetOutputFilter DEFLATE
    </IfModule>
</Files>

<Files "Packages*">
    <IfModule mod_deflate.c>
        SetOutputFilter DEFLATE
    </IfModule>
</Files>

<Files "Sources*">
    <IfModule mod_deflate.c>
        SetOutputFilter DEFLATE
    </IfModule>
</Files>
EOF

cat > "$REPO_DIR/header.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>PiTrac Package Repository</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
<div class="header">
    <h1>PiTrac Package Repository</h1>
    <p>Debian/Raspbian packages for the PiTrac golf ball tracking system.</p>
    <p><strong>Repository URL:</strong> <code>deb [arch=arm64] https://your-domain.com/repo bookworm main</code></p>
</div>
EOF

cat > "$REPO_DIR/footer.html" << 'EOF'
<div style="margin-top: 20px; padding-top: 10px; border-top: 1px solid #ccc; font-size: 0.9em; color: #666;">
    <p>PiTrac Package Repository - For installation instructions, see the project documentation.</p>
</div>
</body>
</html>
EOF

cat > "$REPO_DIR/README.md" << 'EOF'
# PiTrac APT Repository

This is the official APT repository for PiTrac packages.

## Quick Setup

Add this repository to your system:

```bash
# Add repository
echo "deb [arch=arm64] https://your-domain.com/repo bookworm main" | sudo tee /etc/apt/sources.list.d/pitrac.list

# Add GPG key (if repository is signed)
curl -fsSL https://your-domain.com/repo/public.key | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg

# Update and install
sudo apt update
sudo apt install pitrac
```

## Available Packages

- `pitrac` - Main PiTrac application
- `pitrac-dev` - Development files
- `liblgpio1` - GPIO library runtime
- `liblgpio-dev` - GPIO library development files
- `libmsgpack-cxx-dev` - MessagePack C++ headers
- `libopencv4.11` - OpenCV runtime libraries
- `libopencv-dev` - OpenCV development files

## Repository Structure

- `dists/` - Distribution metadata
- `pool/` - Package files
- `conf/` - Repository configuration (reprepro)

## Supported Architectures

- Package building may occur on x86_64 systems using Docker cross-compilation, but packages are arm64 only
- `arm64` - ARM 64-bit (Raspberry Pi 4/5)

## Components

- `main` - Main packages
- `contrib` - Packages with dependencies outside main
- `non-free` - Proprietary packages
EOF

if [ -n "$GPG_KEY_ID" ]; then
    log_info "Exporting GPG public key..."
    gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"
    log_success "GPG public key exported to public.key"
fi

cat > "$REPO_DIR/add-package.sh" << 'EOF'
#!/bin/bash
# Add package to repository
# Usage: ./add-package.sh <package.deb> [component]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package.deb> [component]"
    exit 1
fi

PACKAGE="$1"
COMPONENT="${2:-main}"

if [ ! -f "$PACKAGE" ]; then
    echo "Error: Package file not found: $PACKAGE"
    exit 1
fi

echo "Adding package: $PACKAGE (component: $COMPONENT)"

# Include the package
reprepro includedeb bookworm "$PACKAGE"

echo "Package added successfully"
EOF

chmod +x "$REPO_DIR/add-package.sh"

cat > "$REPO_DIR/remove-package.sh" << 'EOF'
#!/bin/bash
# Remove package from repository
# Usage: ./remove-package.sh <package-name>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <package-name>"
    exit 1
fi

PACKAGE="$1"

echo "Removing package: $PACKAGE"

# Remove the package
reprepro remove bookworm "$PACKAGE"

echo "Package removed successfully"
EOF

chmod +x "$REPO_DIR/remove-package.sh"

cat > "$REPO_DIR/list-packages.sh" << 'EOF'
#!/bin/bash
# List packages in repository
# Usage: ./list-packages.sh [--verbose]

if [ "${1:-}" = "--verbose" ]; then
    echo "Detailed package listing:"
    reprepro list bookworm
else
    echo "Package summary:"
    reprepro listmatched bookworm '*' | cut -d' ' -f2 | sort | uniq -c
fi
EOF

chmod +x "$REPO_DIR/list-packages.sh"

chmod -R 755 "$REPO_DIR"
find "$REPO_DIR" -type f -name "*.sh" -exec chmod +x {} \;

log_success "APT repository initialized successfully!"
echo ""
log_info "Repository location: $REPO_DIR"
log_info "Configuration: $REPO_DIR/conf/"
echo ""
log_info "To add packages:"
log_info "  cd $REPO_DIR && ./add-package.sh /path/to/package.deb"
echo ""
log_info "To list packages:"
log_info "  cd $REPO_DIR && ./list-packages.sh"
echo ""

if [ -n "$GPG_KEY_ID" ]; then
    log_info "Repository is configured for signing with GPG key: $GPG_KEY_ID"
    log_info "Public key exported to: $REPO_DIR/public.key"
else
    log_warn "Repository is not configured for package signing"
    log_info "To enable signing, create a GPG key and update conf/distributions"
fi