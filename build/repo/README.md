# PiTrac APT Repository

This is the official APT repository for PiTrac packages.

## Quick Setup

Add this repository to your system:

### For Debian 12 (Bookworm)

```bash
# Add repository
echo "deb [arch=arm64] https://your-domain.com/repo bookworm main" | sudo tee /etc/apt/sources.list.d/pitrac.list

# Add GPG key (if repository is signed)
curl -fsSL https://your-domain.com/repo/public.key | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg

# Update and install
sudo apt update
sudo apt install pitrac
```

### For Debian 13 (Trixie)

```bash
# Add repository
echo "deb [arch=arm64] https://your-domain.com/repo trixie main" | sudo tee /etc/apt/sources.list.d/pitrac.list

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
