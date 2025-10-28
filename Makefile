# PiTrac Package Build System
# Builds .deb packages for arm64 architecture (Raspberry Pi 5)
# Dependencies: lgpio -> msgpack -> activemq -> opencv -> pitrac

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configuration
PROJECT_ROOT := $(shell pwd)
BUILD_DIR := $(PROJECT_ROOT)/build
ARTIFACT_DIR := $(BUILD_DIR)/artifacts
DEB_DIR := $(BUILD_DIR)/debs
REPO_DIR := $(BUILD_DIR)/repo
DOCKER_BUILD_OPTS := --no-cache

# Supported distributions
DISTROS := bookworm trixie

# Shared version configuration (same across distros)
LGPIO_VERSION := 0.2.2-1
MSGPACK_VERSION := 6.1.1-1
ACTIVEMQ_VERSION := 3.9.5-1
OPENCV_VERSION := 4.11.0-1
PITRAC_VERSION := $(shell date +%Y.%m.%d)-1

# Distro-specific versions (when they differ)
BOOKWORM_ONNXRUNTIME_VERSION := 1.17.3-1
TRIXIE_ONNXRUNTIME_VERSION := 1.22.1-1

# PiTrac source repository configuration
PITRAC_REPO ?= https://github.com/jamespilgrim/PiTrac.git
PITRAC_BRANCH ?= main

# Architecture support - Raspberry Pi 5 is arm64 only
ARCHS := arm64
CURRENT_ARCH := $(shell dpkg --print-architecture)

# Package build order (respects dependencies)
PACKAGES := lgpio msgpack activemq opencv onnxruntime pitrac

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Logging functions
define log_info
	@echo -e "$(BLUE)[INFO]$(NC) $(1)"
endef

define log_success
	@echo -e "$(GREEN)[SUCCESS]$(NC) $(1)"
endef

define log_warn
	@echo -e "$(YELLOW)[WARN]$(NC) $(1)"
endef

define log_error
	@echo -e "$(RED)[ERROR]$(NC) $(1)"
endef

# Dependency matrix
LGPIO_DEPS :=
MSGPACK_DEPS :=
ACTIVEMQ_DEPS :=
OPENCV_DEPS := activemq
ONNXRUNTIME_DEPS :=
PITRAC_DEPS := lgpio msgpack activemq opencv onnxruntime

# Package-specific configuration
LGPIO_DEB_DEPS := build-essential,wget,unzip
MSGPACK_DEB_DEPS := build-essential,cmake,wget,unzip,libboost-dev
ACTIVEMQ_DEB_DEPS := build-essential,cmake,autoconf,automake,libtool,pkg-config,wget,libssl-dev,uuid-dev,libapr1-dev,libaprutil1-dev,libcppunit-dev
OPENCV_DEB_DEPS := build-essential,cmake,git,pkg-config,wget,unzip,zlib1g-dev,libgtk-3-dev,libavcodec-dev,libavformat-dev,libswscale-dev,libv4l-dev,libxvidcore-dev,libx264-dev,libjpeg-dev,libpng-dev,libtiff-dev,gfortran,openexr,libatlas-base-dev,python3-dev,python3-numpy,libtbb-dev,libdc1394-dev,libopenexr-dev,libgstreamer-plugins-base1.0-dev,libgstreamer1.0-dev,libglu1-mesa-dev,libgl1-mesa-dev
ONNXRUNTIME_DEB_DEPS := build-essential,cmake,git,pkg-config,python3-dev,python3-pip,python3-numpy,patchelf,protobuf-compiler,libprotobuf-dev,libre2-dev,libssl-dev,libcurl4-openssl-dev,ninja-build
PITRAC_DEB_DEPS := build-essential,meson,ninja-build,pkg-config,git,libboost-system1.74.0,libboost-thread1.74.0,libboost-filesystem1.74.0,libboost-program-options1.74.0,libboost-timer1.74.0,libboost-log1.74.0,libboost-regex1.74.0,libboost-dev,libcamera0.0.3,libcamera-dev,libfmt-dev,libssl-dev,liblgpio-dev,liblgpio1,libmsgpack-cxx-dev,libactivemq-cpp,libactivemq-cpp-dev,libapr1,libaprutil1,libapr1-dev,libaprutil1-dev,libyaml-cpp-dev,libssl3,libonnxruntime1.17.3,libonnxruntime-dev

.PHONY: help setup clean build-all build-all-bookworm build-all-trixie $(foreach pkg,$(PACKAGES),build-$(pkg)-bookworm build-$(pkg)-trixie) repo-update install-deps check-docker

help: ## Show this help message
	@echo "PiTrac Package Build System - Multi-Distribution Support"
	@echo ""
	@echo "Supported Distributions: $(DISTROS)"
	@echo "Supported Architectures: $(ARCHS)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Multi-Distribution Build Targets:"
	@echo "  build-all                   Build all packages for all distributions"
	@echo "  build-all-bookworm          Build all packages for Debian 12 (Bookworm)"
	@echo "  build-all-trixie            Build all packages for Debian 13 (Trixie)"
	@echo ""
	@echo "Per-Package Build Targets:"
	@echo "  build-<package>-bookworm    Build specific package for Bookworm"
	@echo "  build-<package>-trixie      Build specific package for Trixie"
	@echo ""
	@echo "Available packages: $(PACKAGES)"
	@echo ""
	@echo "Repository Targets:"
	@echo "  repo-init                   Initialize APT repository (both distros)"
	@echo "  repo-update                 Update APT repository with built packages"
	@echo "  repo-clean                  Clean APT repository"
	@echo ""
	@echo "Utility Targets:"
	@echo "  setup                       Create build directories and setup environment"
	@echo "  clean                       Clean all build artifacts"
	@echo "  install-deps                Install build dependencies"
	@echo "  check-docker                Verify Docker and QEMU setup"
	@echo "  versions                    Show current package versions"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-27s %s\n", $$1, $$2}'

versions: ## Show current package versions
	$(call log_info,Package versions by distribution:)
	@echo ""
	@echo "Shared versions (same across distros):"
	@echo "  lgpio:       $(LGPIO_VERSION)"
	@echo "  msgpack:     $(MSGPACK_VERSION)"
	@echo "  activemq:    $(ACTIVEMQ_VERSION)"
	@echo "  opencv:      $(OPENCV_VERSION)"
	@echo "  pitrac:      $(PITRAC_VERSION)"
	@echo ""
	@echo "Bookworm-specific:"
	@echo "  onnxruntime: $(BOOKWORM_ONNXRUNTIME_VERSION)"
	@echo ""
	@echo "Trixie-specific:"
	@echo "  onnxruntime: $(TRIXIE_ONNXRUNTIME_VERSION) (Eigen hash fix included)"

setup: ## Create build directories and setup environment
	$(call log_info,Setting up multi-distro build environment...)
	@mkdir -p $(BUILD_DIR) $(REPO_DIR)
	@mkdir -p $(foreach distro,$(DISTROS),$(DEB_DIR)/$(distro)/arm64)
	@mkdir -p $(foreach distro,$(DISTROS),$(ARTIFACT_DIR)/$(distro))
	@mkdir -p $(foreach pkg,$(PACKAGES),$(BUILD_DIR)/$(pkg))
	$(call log_success,Build environment ready for $(DISTROS))

check-docker: ## Verify Docker and QEMU setup
	$(call log_info,Checking Docker installation...)
	@docker --version >/dev/null 2>&1 || ($(call log_error,Docker not found. Please install Docker) && exit 1)
	$(call log_info,Setting up QEMU for cross-platform builds...)
	@docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1
	$(call log_success,Docker and QEMU ready for cross-platform builds)

install-deps: ## Install host build dependencies
	$(call log_info,Installing build dependencies...)
	@sudo apt-get update
	@sudo apt-get install -y \
		build-essential \
		docker.io \
		reprepro \
		dpkg-dev \
		fakeroot \
		devscripts \
		dh-make \
		git \
		wget \
		curl
	$(call log_success,Build dependencies installed)

clean:
	$(call log_warn,Cleaning build artifacts...)
	@rm -rf $(BUILD_DIR)
	@docker rmi $(shell docker images -q 'pitrac-*' 2>/dev/null) 2>/dev/null || true
	$(call log_success,Build artifacts cleaned)

# High-level build targets
build-all: build-all-bookworm build-all-trixie ## Build all packages for all distributions
	$(call log_success,All packages built for all distributions)

build-all-bookworm: setup check-docker build-lgpio-bookworm build-msgpack-bookworm build-activemq-bookworm build-opencv-bookworm build-onnxruntime-bookworm build-pitrac-bookworm ## Build all packages for Bookworm
	$(call log_success,All Bookworm packages built successfully)

build-all-trixie: setup check-docker build-lgpio-trixie build-msgpack-trixie build-activemq-trixie build-opencv-trixie build-onnxruntime-trixie build-pitrac-trixie ## Build all packages for Trixie
	$(call log_success,All Trixie packages built successfully)

# Bookworm build targets
build-lgpio-bookworm: setup
	$(call log_info,Building lgpio for bookworm/arm64...)
	@./scripts/build-package.sh lgpio arm64 $(LGPIO_VERSION) bookworm
	$(call log_success,lgpio built for bookworm/arm64)

build-msgpack-bookworm: build-lgpio-bookworm
	$(call log_info,Building msgpack for bookworm/arm64...)
	@./scripts/build-package.sh msgpack arm64 $(MSGPACK_VERSION) bookworm
	$(call log_success,msgpack built for bookworm/arm64)

build-activemq-bookworm: build-msgpack-bookworm
	$(call log_info,Building activemq for bookworm/arm64...)
	@./scripts/build-package.sh activemq arm64 $(ACTIVEMQ_VERSION) bookworm
	$(call log_success,activemq built for bookworm/arm64)

build-opencv-bookworm: build-activemq-bookworm
	$(call log_info,Building opencv for bookworm/arm64...)
	@./scripts/build-package.sh opencv arm64 $(OPENCV_VERSION) bookworm
	$(call log_success,opencv built for bookworm/arm64)

build-onnxruntime-bookworm: setup
	$(call log_info,Building onnxruntime $(BOOKWORM_ONNXRUNTIME_VERSION) for bookworm/arm64...)
	@./scripts/build-package.sh onnxruntime arm64 $(BOOKWORM_ONNXRUNTIME_VERSION) bookworm
	$(call log_success,onnxruntime built for bookworm/arm64)

build-pitrac-bookworm: build-opencv-bookworm build-onnxruntime-bookworm
	$(call log_info,Building pitrac for bookworm/arm64...)
	@PITRAC_REPO=$(PITRAC_REPO) PITRAC_BRANCH=$(PITRAC_BRANCH) ./scripts/build-package.sh pitrac arm64 $(PITRAC_VERSION) bookworm
	$(call log_success,pitrac built for bookworm/arm64)

# Trixie build targets
build-lgpio-trixie: setup
	$(call log_info,Building lgpio for trixie/arm64...)
	@./scripts/build-package.sh lgpio arm64 $(LGPIO_VERSION) trixie
	$(call log_success,lgpio built for trixie/arm64)

build-msgpack-trixie: build-lgpio-trixie
	$(call log_info,Building msgpack for trixie/arm64...)
	@./scripts/build-package.sh msgpack arm64 $(MSGPACK_VERSION) trixie
	$(call log_success,msgpack built for trixie/arm64)

build-activemq-trixie: build-msgpack-trixie
	$(call log_info,Building activemq for trixie/arm64...)
	@./scripts/build-package.sh activemq arm64 $(ACTIVEMQ_VERSION) trixie
	$(call log_success,activemq built for trixie/arm64)

build-opencv-trixie: build-activemq-trixie
	$(call log_info,Building opencv for trixie/arm64...)
	@./scripts/build-package.sh opencv arm64 $(OPENCV_VERSION) trixie
	$(call log_success,opencv built for trixie/arm64)

build-onnxruntime-trixie: setup
	$(call log_info,Building onnxruntime $(TRIXIE_ONNXRUNTIME_VERSION) for trixie/arm64...)
	@./scripts/build-package.sh onnxruntime arm64 $(TRIXIE_ONNXRUNTIME_VERSION) trixie
	$(call log_success,onnxruntime built for trixie/arm64)

build-pitrac-trixie: build-opencv-trixie build-onnxruntime-trixie
	$(call log_info,Building pitrac for trixie/arm64...)
	@PITRAC_REPO=$(PITRAC_REPO) PITRAC_BRANCH=$(PITRAC_BRANCH) ./scripts/build-package.sh pitrac arm64 $(PITRAC_VERSION) trixie
	$(call log_success,pitrac built for trixie/arm64)

repo-init: setup
	$(call log_info,Initializing APT repository...)
	@./scripts/repo-init.sh $(REPO_DIR)
	$(call log_success,APT repository initialized)

repo-update:
	$(call log_info,Updating APT repository...)
	@./scripts/repo-update.sh $(REPO_DIR) $(DEB_DIR)
	$(call log_success,APT repository updated)

repo-clean: 
	$(call log_warn,Cleaning APT repository...)
	@rm -rf $(REPO_DIR)
	$(call log_success,APT repository cleaned)

list-debs:
	@find $(DEB_DIR) -name "*.deb" -type f 2>/dev/null | sort || echo "No packages built yet"

check-deps: 
	$(call log_info,Checking build dependencies...)
	@which docker >/dev/null || ($(call log_error,Docker not found) && exit 1)
	@which reprepro >/dev/null || ($(call log_error,reprepro not found) && exit 1)
	@which dpkg-deb >/dev/null || ($(call log_error,dpkg-deb not found) && exit 1)
	$(call log_success,All dependencies available)

.PHONY: incremental-build
incremental-build:
	$(call log_info,Detecting changes...)
	@./scripts/incremental-build.sh

.PHONY: ci-build ci-test ci-deploy
ci-build: check-deps build-all
	$(call log_success,CI build completed)

ci-test:
	$(call log_info,Running package tests...)
	@./scripts/test-packages.sh $(DEB_DIR)
	$(call log_success,Package tests passed)

ci-deploy: repo-update
	$(call log_success,CI deployment completed)

.PHONY: apt-init apt-check apt-list apt-list-verbose apt-clean apt-add apt-remove apt-export-key apt-setup-client apt-export apt-update

apt-init:
	@echo "Initializing PiTrac APT repository..."
	@if [ ! -f conf/distributions ]; then \
		echo "Error: Repository not properly set up. conf/distributions missing."; \
		exit 1; \
	fi
	@mkdir -p incoming tmp
	@echo "APT repository initialized. You may now add packages."

apt-check:
	@echo "Checking APT repository integrity..."
	@reprepro check

apt-list:
	@./scripts/list-packages.sh

apt-list-verbose: 
	@./scripts/list-packages.sh --verbose

apt-clean:
	@echo "Cleaning orphaned files..."
	@reprepro deleteunreferenced
	@echo "Cleanup complete."

apt-add:
	@if [ -z "$(PKG)" ]; then \
		echo "Error: PKG parameter required. Usage: make apt-add PKG=path/to/package.deb"; \
		exit 1; \
	fi
	@./scripts/add-package.sh "$(PKG)" "$(COMP)"

apt-remove:
	@if [ -z "$(PKG)" ]; then \
		echo "Error: PKG parameter required. Usage: make apt-remove PKG=package-name"; \
		exit 1; \
	fi
	@./scripts/remove-package.sh "$(PKG)"

apt-export-key:
	@./scripts/setup-gpg.sh export

apt-setup-client:
	@echo "APT Repository Client Setup Instructions"
	@echo "========================================"
	@echo ""
	@echo "1. Add repository to APT sources:"
	@echo "   sudo tee /etc/apt/sources.list.d/pitrac.list << 'EOF'"
	@echo "   deb [arch=arm64 signed-by=/usr/share/keyrings/pitrac-archive-keyring.gpg] https://raw.githubusercontent.com/YOUR_USERNAME/pitrac/main/packages bookworm main contrib non-free"
	@echo "   EOF"
	@echo ""
	@echo "2. Add GPG key:"
	@echo "   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/pitrac/main/packages/public.key | sudo gpg --dearmor -o /usr/share/keyrings/pitrac-archive-keyring.gpg"
	@echo ""
	@echo "3. Update APT cache:"
	@echo "   sudo apt update"
	@echo ""
	@echo "4. Install packages:"
	@echo "   sudo apt install package-name"
	@echo ""
	@echo "Note: Replace YOUR_USERNAME with your actual GitHub username"

apt-export:
	@echo "Exporting APT repository metadata for all distributions..."
	@reprepro export bookworm
	@reprepro export trixie
	@echo "Export complete for all distributions."

apt-update: apt-export apt-clean
	@echo "APT repository updated for all distributions."