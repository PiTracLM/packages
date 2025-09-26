#!/bin/bash
# GPG Key Setup for APT Repository
# This script generates and manages GPG keys for signing the repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
GPG_KEY_NAME="PiTrac APT Repository"
GPG_KEY_EMAIL="packages@pitrac.local"
GPG_KEY_COMMENT="PiTrac Package Signing Key"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_dependencies() {
    if ! command -v gpg &> /dev/null; then
        log_error "gpg is not installed. Please install it first."
    fi
}

generate_key() {
    log_info "Generating new GPG key for repository signing..."

    if gpg --list-secret-keys | grep -q "$GPG_KEY_EMAIL"; then
        log_warn "GPG key for $GPG_KEY_EMAIL already exists"
        read -p "Do you want to generate a new key? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Using existing key"
            return
        fi
    fi

    cat > /tmp/gpg_batch_config <<EOF
%echo Generating GPG key for PiTrac APT Repository
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GPG_KEY_NAME
Name-Comment: $GPG_KEY_COMMENT
Name-Email: $GPG_KEY_EMAIL
Expire-Date: 2y
%no-protection
%commit
%echo Done
EOF

    gpg --batch --generate-key /tmp/gpg_batch_config
    rm -f /tmp/gpg_batch_config

    log_info "GPG key generated successfully"
}

export_public_key() {
    log_info "Exporting public key..."

    KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "$GPG_KEY_EMAIL" 2>/dev/null | grep sec | awk '{print $2}' | cut -d'/' -f2)

    if [ -z "$KEY_ID" ]; then
        log_error "Could not find GPG key ID for $GPG_KEY_EMAIL"
    fi

    gpg --armor --export "$KEY_ID" > "$REPO_ROOT/pitrac-repo.asc"
    log_info "Public key exported to $REPO_ROOT/pitrac-repo.asc"

    gpg --armor --export "$KEY_ID" > "$REPO_ROOT/conf/apt-key.asc"
    log_info "Public key copied to conf/apt-key.asc"

    echo "$KEY_ID" > "$REPO_ROOT/conf/key-id"
    log_info "Key ID saved to conf/key-id: $KEY_ID"

    if [ -f "$REPO_ROOT/conf/distributions" ]; then
        if ! grep -q "SignWith:" "$REPO_ROOT/conf/distributions"; then
            sed -i "/Codename: bookworm/a SignWith: $KEY_ID" "$REPO_ROOT/conf/distributions"
            log_info "Updated distributions file with signing key"
        fi
    fi
}

setup_github_secret() {
    log_info "Setting up for GitHub..."

    KEY_ID=$(cat "$REPO_ROOT/conf/key-id" 2>/dev/null)
    if [ -z "$KEY_ID" ]; then
        log_error "Key ID not found. Please generate key first."
    fi

    log_info "Exporting private key for GitHub Actions..."
    gpg --armor --export-secret-keys "$KEY_ID" > "$REPO_ROOT/.gpg-private-key.asc"

    cat <<EOF

${GREEN}=== GitHub Setup Instructions ===${NC}

1. The private key has been exported to: .gpg-private-key.asc
   ${YELLOW}WARNING: This file contains your PRIVATE KEY. Handle with care!${NC}

2. Add the following secrets to your GitHub repository:
   - GPG_PRIVATE_KEY: Contents of .gpg-private-key.asc
   - GPG_PASSPHRASE: (empty if no passphrase was set)

3. To add via GitHub CLI:
   ${GREEN}gh secret set GPG_PRIVATE_KEY < .gpg-private-key.asc${NC}

4. The public key for users is at: pitrac-repo.asc
   This will be served from GitHub Pages.

5. ${RED}IMPORTANT:${NC} Delete .gpg-private-key.asc after adding to GitHub secrets!
   ${GREEN}rm .gpg-private-key.asc${NC}

EOF
}

verify_setup() {
    log_info "Verifying GPG setup..."

    KEY_ID=$(cat "$REPO_ROOT/conf/key-id" 2>/dev/null)
    if [ -z "$KEY_ID" ]; then
        log_error "No key ID found in conf/key-id"
    fi

    if ! gpg --list-secret-keys "$KEY_ID" &>/dev/null; then
        log_error "Key $KEY_ID not found in GPG keyring"
    fi

    if [ ! -f "$REPO_ROOT/pitrac-repo.asc" ]; then
        log_error "Public key not exported to pitrac-repo.asc"
    fi

    echo "test" | gpg --clearsign --local-user "$KEY_ID" &>/dev/null || log_error "Failed to sign test message"

    log_info "GPG setup verified successfully!"

    echo
    echo "Key Information:"
    gpg --list-keys "$KEY_ID"
}

show_client_setup() {
    cat <<EOF

${GREEN}=== Client Setup Instructions ===${NC}

To use this repository on client machines:

1. Add the repository to sources.list:
   ${GREEN}echo "deb https://YOUR-GITHUB-USERNAME.github.io/pitrac-packages bookworm main contrib non-free" | sudo tee /etc/apt/sources.list.d/pitrac.list${NC}

2. Import the GPG key:
   ${GREEN}curl -fsSL https://YOUR-GITHUB-USERNAME.github.io/pitrac-packages/pitrac-repo.asc | sudo apt-key add -${NC}

   Or for newer systems (apt-key deprecated):
   ${GREEN}curl -fsSL https://YOUR-GITHUB-USERNAME.github.io/pitrac-packages/pitrac-repo.asc | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg${NC}
   ${GREEN}echo "deb [signed-by=/usr/share/keyrings/pitrac-archive-keyring.gpg] https://YOUR-GITHUB-USERNAME.github.io/pitrac-packages bookworm main contrib non-free" | sudo tee /etc/apt/sources.list.d/pitrac.list${NC}

3. Update and install packages:
   ${GREEN}sudo apt update${NC}
   ${GREEN}sudo apt install pitrac${NC}

EOF
}

main() {
    check_dependencies

    echo
    echo "PiTrac APT Repository GPG Setup"
    echo "================================"
    echo
    echo "1) Generate new GPG key"
    echo "2) Export public key"
    echo "3) Setup for GitHub Actions"
    echo "4) Verify setup"
    echo "5) Show client setup instructions"
    echo "6) Complete setup (all of the above)"
    echo "0) Exit"
    echo
    read -p "Choose an option: " choice

    case $choice in
        1)
            generate_key
            ;;
        2)
            export_public_key
            ;;
        3)
            setup_github_secret
            ;;
        4)
            verify_setup
            ;;
        5)
            show_client_setup
            ;;
        6)
            generate_key
            export_public_key
            setup_github_secret
            verify_setup
            show_client_setup
            ;;
        0)
            exit 0
            ;;
        *)
            log_error "Invalid option"
            ;;
    esac
}

main