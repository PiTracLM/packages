# PiTrac Package Repository

## What This Is

This repository builds and distributes Debian packages for the PiTrac golf ball tracking system. It creates `.deb` packages specifically for Raspberry Pi 5 (arm64 architecture) and hosts them through an APT repository on GitHub Pages.

The build system handles two distinct challenges:
- Building external dependencies (lgpio, msgpack, opencv) that aren't available in standard repositories with the right versions or configurations
- Packaging the PiTrac application itself from its separate source repository

## Why It Exists

Raspberry Pi development typically involves compiling from source on the device itself, which takes hours for large projects like OpenCV. This repository solves that by providing pre-built packages that install in seconds. The packages are built with specific optimizations for the Pi 5's hardware and include only the features PiTrac needs.

The separation between this packaging repository and the main PiTrac source repository follows standard Debian packaging practices where packaging metadata and build scripts live separately from the application source.

## System Architecture

### Repository Structure

```
packages/                         # This repository
├── docker/                      # Dockerfiles for cross-compilation
│   ├── Dockerfile.lgpio        # GPIO library builder
│   ├── Dockerfile.msgpack      # MessagePack C++ builder
│   ├── Dockerfile.opencv       # OpenCV with DNN/ONNX support
│   └── Dockerfile.pitrac       # Main application builder
├── scripts/                     # Build automation
│   ├── build-package.sh        # Docker build orchestrator
│   ├── build-*-native-pi.sh   # Native Pi build scripts
│   ├── incremental-build.sh   # Change detection builds
│   ├── version-manager.sh     # Version and changelog management
│   ├── repo-init.sh           # Repository initialization
│   ├── repo-update.sh         # Package inclusion
│   └── setup-gpg.sh           # GPG key management
├── conf/                        # APT repository configuration
│   └── distributions           # reprepro configuration
├── build/                       # Build outputs (gitignored)
│   ├── debs/                   # Built packages by architecture
│   └── repo/                   # Local APT repository
├── dists/                       # APT repository metadata
├── pool/                        # APT repository packages
└── Makefile                     # Primary build interface
```

### Build Dependency Chain

The packages must be built in this order due to dependencies:

```
lgpio (0.2.2) → msgpack (6.1.1) → opencv (4.11.0) → pitrac
         ↓              ↓                ↓              ↓
   GPIO access    Serialization    Computer vision  Application
```

### Two Build Methods

The system supports two build approaches, each with specific use cases:

**1. Docker Cross-Compilation (Primary Method)**
- Uses QEMU emulation to build arm64 packages on any host
- Consistent, reproducible builds in clean environments
- Suitable for CI/CD and most packages
- Slower but more portable

**2. Native Raspberry Pi Builds (When Required)**
- Builds directly on Pi hardware
- Required when QEMU can't handle specific ARM instructions
- Faster for large C++ projects like OpenCV
- Provides full hardware optimization support

## Building Packages

### Prerequisites

On your build machine (can be x86_64 or arm64):

```bash
# Install required tools
sudo apt update
sudo apt install -y docker.io reprepro gpg dpkg-dev git make

# Add user to docker group (logout/login after)
sudo usermod -aG docker $USER

# Verify Docker
docker --version
```

### Quick Start

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/pitrac-packages.git
cd pitrac-packages

# Setup build environment
make setup
make check-docker

# Build all packages (uses Docker/QEMU)
make build-all

# Initialize APT repository
make repo-init

# Add packages to repository
make repo-update
```

### Building Individual Packages

#### Docker Builds (Cross-Platform)

```bash
# Build specific package
make build-lgpio        # GPIO library
make build-msgpack      # Serialization library
make build-opencv       # Computer vision (4+ hours with QEMU)
make build-pitrac       # Main application

# Build with specific source (for PiTrac development)
make build-pitrac PITRAC_REPO=file:///path/to/local/PiTrac

# Build from specific branch/tag
make build-pitrac PITRAC_BRANCH=v1.2.3
```

#### Native Pi Builds

When QEMU emulation fails or is too slow, build directly on a Raspberry Pi:

```bash
# On a Raspberry Pi 5
cd pitrac-packages/scripts

# Build OpenCV natively (2-3 hours vs 4+ with QEMU)
./build-opencv-native-pi.sh

# Build all packages natively
./build-all-native-pi.sh

# Copy resulting packages to build machine
scp *.deb user@buildmachine:~/pitrac-packages/build/debs/arm64/
```

The native build scripts detect the Pi model and apply appropriate optimizations:
- Pi 5: Cortex-A76 optimizations, NEON SIMD
- Pi 4: Cortex-A72 optimizations
- Others: Generic ARMv8 optimizations

### Incremental Builds

The incremental build system only rebuilds packages that have changed:

```bash
# Detect and build only changed packages
./scripts/incremental-build.sh

# Force rebuild specific packages if changed
./scripts/incremental-build.sh opencv pitrac

# The system tracks changes via:
# - Source file MD5 hashes
# - Dockerfile modifications
# - Dependency updates
```

### Version Management

Package versions follow different strategies:

```bash
# Show current versions
./scripts/version-manager.sh show

# Dependencies use semantic versioning
./scripts/version-manager.sh set lgpio 0.2.3
./scripts/version-manager.sh increment opencv minor

# PiTrac uses date-based versioning
# Automatically: 2024.01.15-1
./scripts/version-manager.sh release pitrac revision "Camera optimizations"
```

## Repository Management

### GPG Key Setup

Package signing ensures authenticity. Generate a signing key:

```bash
# Interactive setup with menu
./scripts/setup-gpg.sh

# Options:
# 1. Generate new key
# 2. Export public key (for users)
# 3. Export private key (backup)
# 4. List keys
# 5. Configure reprepro
# 6. Complete setup (does everything)

# The public key will be saved as:
# - pitrac-repo.asc (for distribution)
# - conf/apt-key.asc (for reprepro)
```

For CI/CD, export the private key and add to GitHub Secrets:
```bash
gpg --armor --export-secret-keys YOUR_KEY_ID > private.key
# Add contents to GitHub secret: SIGNING_KEY
```

### Repository Operations

```bash
# Initialize repository structure
make repo-init

# Add built packages to repository
make repo-update

# Add individual package manually
reprepro -Vb . includedeb bookworm build/debs/arm64/package_1.0_arm64.deb

# List repository contents
make repo-list
reprepro list bookworm

# Remove package
reprepro remove bookworm package-name

# Check repository integrity
reprepro check

# Clean unreferenced files
reprepro deleteunreferenced
```

### Repository Structure

The APT repository follows standard Debian layout:

```
dists/
└── bookworm/                    # Debian 12 codename
    ├── Release                  # Repository metadata
    ├── Release.gpg              # Signature
    └── main/                    # Component
        └── binary-arm64/        # Architecture
            ├── Packages         # Package index
            └── Packages.gz      # Compressed index

pool/
└── main/                        # Component
    └── [a-z]/                   # First letter of package
        └── package/             # Package name
            └── *.deb            # Package files
```

## Deployment

### GitHub Pages Hosting

The repository automatically deploys to GitHub Pages:

1. **Enable GitHub Pages**
   - Repository Settings → Pages
   - Source: Deploy from branch
   - Branch: main, / (root)

2. **Automatic Deployment**
   ```bash
   # Commits to main trigger deployment
   git add .
   git commit -m "Add opencv 4.11.0 packages"
   git push origin main
   ```

3. **Access Repository**
   ```
   https://YOUR_USERNAME.github.io/pitrac-packages/
   ```

### Manual Deployment

For custom hosting:

```bash
# Sync repository to web server
rsync -av --delete dists/ pool/ server:/var/www/apt/
rsync -av pitrac-repo.asc server:/var/www/apt/

# Or use GitHub releases
gh release create v1.0 build/debs/arm64/*.deb
```

## Client Installation

### Adding the Repository

On Raspberry Pi systems:

```bash
# Add repository to APT sources
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/pitrac.gpg] \
  https://YOUR_USERNAME.github.io/pitrac-packages bookworm main" | \
  sudo tee /etc/apt/sources.list.d/pitrac.list

# Add repository signing key
curl -fsSL https://YOUR_USERNAME.github.io/pitrac-packages/pitrac-repo.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/pitrac.gpg

# Update package index
sudo apt update
```

### Installing Packages

```bash
# Install everything
sudo apt install pitrac

# Install specific components
sudo apt install liblgpio1 liblgpio-dev     # GPIO library
sudo apt install libmsgpack-cxx-dev         # MessagePack headers
sudo apt install libopencv4.11              # OpenCV runtime
sudo apt install libopencv-dev              # OpenCV development

# The pitrac package pulls in all dependencies automatically
```

### Version Pinning

To prevent unwanted upgrades:

```bash
# Pin specific version
echo "Package: pitrac
Pin: version 2024.01.15-1
Pin-Priority: 1001" | sudo tee /etc/apt/preferences.d/pitrac

# Hold package at current version
sudo apt-mark hold pitrac
```

## CI/CD Pipeline

### GitHub Actions Workflow

The `.github/workflows/build-packages.yml` workflow:

1. **Triggers**
   - Push to main/develop branches
   - Pull requests
   - Manual workflow dispatch
   - Repository dispatch from PiTrac repo

2. **Build Matrix**
   - Builds all packages for arm64
   - Parallel builds where possible
   - Caches Docker layers

3. **Deployment**
   - Updates APT repository
   - Commits to main branch
   - GitHub Pages publishes automatically

### Cross-Repository Integration

Link package builds to PiTrac releases:

```yaml
# In PiTrac repo: .github/workflows/trigger-packages.yml
name: Trigger Package Build
on:
  push:
    tags: ['v*']
jobs:
  trigger:
    runs-on: ubuntu-latest
    steps:
      - uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.PACKAGES_TOKEN }}
          repository: YOUR_USERNAME/pitrac-packages
          event-type: build-release
          client-payload: '{"tag": "${{ github.ref_name }}"}'
```

### Build Optimization

Speed up CI builds:

```bash
# Use GitHub Actions cache
- uses: actions/cache@v3
  with:
    path: build/cache
    key: ${{ runner.os }}-build-${{ hashFiles('docker/**') }}

# Parallel builds in workflow
strategy:
  matrix:
    package: [lgpio, msgpack, opencv, pitrac]
```

## Package Details

### lgpio (0.2.2-1)

Lightweight GPIO library for Raspberry Pi:
- Replaces deprecated wiringPi
- Kernel-based GPIO access via /dev/gpiochip
- No sudo required with proper permissions
- Packages: `liblgpio1` (runtime), `liblgpio-dev` (headers)

### msgpack (6.1.1-1)

High-performance binary serialization:
- Header-only C++ library
- Zero-copy operations
- Smaller than JSON, faster than Protocol Buffers
- Package: `libmsgpack-cxx-dev`

### opencv (4.11.0-1)

Computer vision optimized for PiTrac:
- DNN module for YOLO object detection
- ONNX runtime support
- Video I/O with V4L2 and GStreamer
- Removed: Python bindings, Java, unnecessary modules
- Build time: 2-3 hours native, 4+ hours with QEMU
- Packages: `libopencv4.11` (runtime), `libopencv-dev` (development)

### pitrac (date-based)

Main application package:
- Pulls source from GitHub.com/PiTracLM/PiTrac
- Includes systemd service files
- Web interface on port 8080
- Configuration in /etc/pitrac/
- Logs to /var/log/pitrac/
- Package: `pitrac`

## Scripts Reference

### Build Scripts

**build-package.sh**
```bash
./scripts/build-package.sh <package> <arch> <version>
# Example: ./scripts/build-package.sh opencv arm64 4.11.0-1
```

**build-all-native-pi.sh**
```bash
# Run on Raspberry Pi for native builds
./scripts/build-all-native-pi.sh [--skip-deps]
```

**incremental-build.sh**
```bash
# Build only changed packages
./scripts/incremental-build.sh [package1] [package2]
```

### Repository Scripts

**repo-init.sh**
```bash
# Initialize APT repository structure
./scripts/repo-init.sh <repo_dir> <gpg_key_id>
```

**repo-update.sh**
```bash
# Add packages to repository
./scripts/repo-update.sh <repo_dir> <debs_dir>
```

**add-package.sh**
```bash
# Add single package
./scripts/add-package.sh <deb_file> [component]
```

### Utility Scripts

**version-manager.sh**
```bash
# Version management
./scripts/version-manager.sh <command> [args]
# Commands: show, set, increment, release
```

**test-packages.sh**
```bash
# Validate built packages
./scripts/test-packages.sh <debs_dir>
```

**setup-gpg.sh**
```bash
# GPG key management menu
./scripts/setup-gpg.sh
```

## Troubleshooting

### Build Issues

**Docker build fails with "exec format error"**
```bash
# QEMU not setup properly
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
make check-docker
```

**OpenCV build crashes or hangs**
```bash
# QEMU can't handle some AVX instructions
# Solution: Build natively on Raspberry Pi
ssh pi@raspberrypi
cd pitrac-packages/scripts
./build-opencv-native-pi.sh
```

**Out of space during build**
```bash
# Docker uses lots of space
docker system prune -a
# Increase Docker storage in settings
# Or use external volume for builds
```

### Repository Issues

**"The repository does not have a Release file"**
```bash
# Repository not initialized
make repo-init
make repo-update
# Check GitHub Pages is enabled
```

**GPG signature verification failed**
```bash
# Key mismatch or not installed
curl -fsSL https://YOUR_USERNAME.github.io/pitrac-packages/pitrac-repo.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/pitrac.gpg
# Update sources.list to reference correct key
```

**Package conflicts during installation**
```bash
# Check installed versions
dpkg -l | grep -E "lgpio|msgpack|opencv|pitrac"
# Remove conflicting packages
sudo apt remove --purge conflicting-package
# Force overwrite (careful)
sudo dpkg -i --force-overwrite package.deb
```

### Development Issues

**Changes not reflected in build**
```bash
# Docker caching issue
make clean
docker build --no-cache -f docker/Dockerfile.pitrac .
# Or force rebuild
./scripts/incremental-build.sh --force pitrac
```

**Can't access local PiTrac source**
```bash
# File URL must be absolute
make build-pitrac PITRAC_REPO=file://$PWD/../PiTrac  # Wrong
make build-pitrac PITRAC_REPO=file:///home/user/PiTrac  # Correct
```

**Native Pi build missing dependencies**
```bash
# Install build dependencies first
sudo apt build-dep opencv
# Or manually install from script
grep "apt-get install" build-opencv-native-pi.sh
```

## Performance Considerations

### Build Times

Typical build times on different systems:

| Package  | Docker/QEMU (x86) | Docker (ARM) | Native Pi 5 | Native Pi 4 |
|----------|-------------------|--------------|-------------|-------------|
| lgpio    | 2 min            | 1 min        | 30 sec      | 45 sec      |
| msgpack  | 1 min            | 30 sec       | 20 sec      | 30 sec      |
| opencv   | 4-5 hours        | 2 hours      | 2-3 hours   | 4-5 hours   |
| pitrac   | 10 min           | 5 min        | 5 min       | 8 min       |

### Optimization Strategies

1. **Use Native Builds for OpenCV**: QEMU emulation makes OpenCV builds extremely slow
2. **Parallel Builds**: The Makefile supports parallel package builds
3. **Incremental Builds**: Only rebuild what changed
4. **Docker Layer Caching**: Dockerfiles are structured to maximize cache hits
5. **ccache**: Native builds can use ccache to speed up recompilation

### Storage Requirements

- Build environment: 20GB minimum
- Each OpenCV build: 8-10GB temporary
- Final packages: ~200MB total
- APT repository: ~250MB with all packages

## Security

### Package Signing

All packages are GPG signed:
- Signature verification happens automatically during apt update
- Users must add the public key to their keyring
- Private key should never be in the repository

### Build Isolation

Docker provides build isolation:
- Each build runs in a clean container
- No host system contamination
- Reproducible builds

### Dependency Verification

The build system verifies:
- Source tarball checksums (where applicable)
- Git commit hashes for source checkouts
- Package dependencies during build

## Maintenance

### Regular Updates

```bash
# Update package versions
./scripts/version-manager.sh increment opencv patch
make build-opencv
make repo-update

# Update dependencies in Dockerfiles
vim docker/Dockerfile.opencv
# Change version numbers, test build

# Regenerate repository metadata
cd build/repo
reprepro export
```

### Monitoring Disk Usage

```bash
# Check build cache size
du -sh build/cache/

# Clean old packages from repository
reprepro --delete clearvanished

# Remove old Docker images
docker image prune -a
```

### Backup

Important files to backup:
- GPG private key (keep secure, offline)
- conf/distributions (repository configuration)
- Package build logs (for debugging)
- Custom Dockerfiles modifications

### Repository Migration

To move to a new host:

```bash
# Export repository
tar czf pitrac-repo-backup.tar.gz dists/ pool/ conf/ *.asc

# On new host
tar xzf pitrac-repo-backup.tar.gz
reprepro --delete clearvanished
reprepro export
```

## Contributing

### Adding a New Package

1. Create Dockerfile:
```dockerfile
# docker/Dockerfile.newpackage
FROM debian:bookworm-slim
# Build instructions...
```

2. Add to Makefile:
```makefile
NEWPACKAGE_VERSION := 1.0.0-1
PACKAGES := lgpio msgpack opencv pitrac newpackage
```

3. Update dependency chain if needed

4. Test build:
```bash
make build-newpackage
```

### Improving Build Times

- Optimize Dockerfiles for better caching
- Add ccache support for C++ builds
- Implement distributed builds
- Use BuildKit features

### Documentation

- Update this README with new features
- Document any new dependencies
- Add examples for new use cases
- Keep troubleshooting section current

## License

The build scripts and packaging files in this repository are provided under the MIT License. Individual packages maintain their original licenses:
- lgpio: Unlicense (public domain)
- msgpack: Boost Software License
- OpenCV: Apache 2.0
- PiTrac: See main repository

## Support

For issues related to:
- **Packaging and builds**: Open issue in this repository
- **PiTrac application**: Use main PiTrac repository
- **Dependency problems**: Check individual package documentation
- **Repository hosting**: Verify GitHub Pages status