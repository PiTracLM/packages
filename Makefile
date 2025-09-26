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

# Version configuration
LGPIO_VERSION := 0.2.2-1
MSGPACK_VERSION := 6.1.1-1
ACTIVEMQ_VERSION := 3.9.5-1
OPENCV_VERSION := 4.11.0-1
PITRAC_VERSION := $(shell date +%Y.%m.%d)-1

# PiTrac source repository configuration
PITRAC_REPO ?= https://github.com/jamespilgrim/PiTrac.git
PITRAC_BRANCH ?= main

# Architecture support - Raspberry Pi 5 is arm64 only
ARCHS := arm64
CURRENT_ARCH := $(shell dpkg --print-architecture)

# Package build order (respects dependencies)
PACKAGES := lgpio msgpack activemq opencv pitrac

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
PITRAC_DEPS := lgpio msgpack activemq opencv

# Package-specific configuration
LGPIO_DEB_DEPS := build-essential,wget,unzip
MSGPACK_DEB_DEPS := build-essential,cmake,wget,unzip,libboost-dev
ACTIVEMQ_DEB_DEPS := build-essential,cmake,autoconf,automake,libtool,pkg-config,wget,libssl-dev,uuid-dev,libapr1-dev,libaprutil1-dev,libcppunit-dev
OPENCV_DEB_DEPS := build-essential,cmake,git,pkg-config,wget,unzip,zlib1g-dev,libgtk-3-dev,libavcodec-dev,libavformat-dev,libswscale-dev,libv4l-dev,libxvidcore-dev,libx264-dev,libjpeg-dev,libpng-dev,libtiff-dev,gfortran,openexr,libatlas-base-dev,python3-dev,python3-numpy,libtbb-dev,libdc1394-dev,libopenexr-dev,libgstreamer-plugins-base1.0-dev,libgstreamer1.0-dev,libglu1-mesa-dev,libgl1-mesa-dev
PITRAC_DEB_DEPS := build-essential,meson,ninja-build,pkg-config,git,libboost-system1.74.0,libboost-thread1.74.0,libboost-filesystem1.74.0,libboost-program-options1.74.0,libboost-timer1.74.0,libboost-log1.74.0,libboost-regex1.74.0,libboost-dev,libcamera0.0.3,libcamera-dev,libfmt-dev,libssl-dev,liblgpio-dev,liblgpio1,libmsgpack-cxx-dev,libactivemq-cpp,libactivemq-cpp-dev,libapr1,libaprutil1,libapr1-dev,libaprutil1-dev,libyaml-cpp-dev,libssl3

.PHONY: help setup clean build-all $(foreach pkg,$(PACKAGES),build-$(pkg)) $(foreach pkg,$(PACKAGES),$(foreach arch,$(ARCHS),build-$(pkg)-$(arch))) repo-update install-deps check-docker

help: ## Show this help message
	@echo "PiTrac Package Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Build Targets:"
	@echo "  build-all                Build all packages for all architectures"
	@echo "  build-<package>          Build specific package for all architectures"
	@echo "  build-<package>-<arch>   Build specific package for specific architecture"
	@echo ""
	@echo "Available packages: $(PACKAGES)"
	@echo "Available architectures: $(ARCHS)"
	@echo ""
	@echo "Repository Targets:"
	@echo "  repo-init               Initialize APT repository"
	@echo "  repo-update             Update APT repository with built packages"
	@echo "  repo-clean              Clean APT repository"
	@echo ""
	@echo "Utility Targets:"
	@echo "  setup                   Create build directories and setup environment"
	@echo "  clean                   Clean all build artifacts"
	@echo "  install-deps            Install build dependencies"
	@echo "  check-docker            Verify Docker and QEMU setup"
	@echo "  versions                Show current package versions"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

versions: ## Show current package versions
	$(call log_info,Package versions:)
	@echo "  lgpio:   $(LGPIO_VERSION)"
	@echo "  msgpack: $(MSGPACK_VERSION)"
	@echo "  activemq: $(ACTIVEMQ_VERSION)"
	@echo "  opencv:  $(OPENCV_VERSION)"
	@echo "  pitrac:  $(PITRAC_VERSION)"

setup: ## Create build directories and setup environment
	$(call log_info,Setting up build environment...)
	@mkdir -p $(BUILD_DIR) $(ARTIFACT_DIR) $(DEB_DIR) $(REPO_DIR)
	@mkdir -p $(foreach arch,$(ARCHS),$(DEB_DIR)/$(arch))
	@mkdir -p $(foreach pkg,$(PACKAGES),$(BUILD_DIR)/$(pkg))
	$(call log_success,Build environment ready)

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

build-all: setup check-docker $(foreach pkg,$(PACKAGES),build-$(pkg))
	$(call log_success,All packages built successfully)

$(foreach pkg,$(PACKAGES),$(eval build-$(pkg): $(foreach arch,$(ARCHS),build-$(pkg)-$(arch))))

define check_package_deps
	$(foreach dep,$($(1)_DEPS),$(if $(wildcard $(DEB_DIR)/*/$(dep)_*.deb),,$(error Dependency $(dep) not built. Run 'make build-$(dep)' first)))
endef

build-lgpio-arm64: setup
	$(call check_package_deps,LGPIO)
	$(call log_info,Building lgpio for arm64...)
	@./scripts/build-package.sh lgpio arm64 $(LGPIO_VERSION)
	$(call log_success,lgpio built for arm64)

build-msgpack-arm64: build-lgpio-arm64
	$(call log_info,Building msgpack for arm64...)
	@./scripts/build-package.sh msgpack arm64 $(MSGPACK_VERSION)
	$(call log_success,msgpack built for arm64)

build-activemq-arm64: build-msgpack-arm64
	$(call log_info,Building activemq for arm64...)
	@./scripts/build-package.sh activemq arm64 $(ACTIVEMQ_VERSION)
	$(call log_success,activemq built for arm64)

build-opencv-arm64: build-activemq-arm64
	$(call log_info,Building opencv for arm64...)
	@./scripts/build-package.sh opencv arm64 $(OPENCV_VERSION)
	$(call log_success,opencv built for arm64)

build-pitrac-arm64: build-opencv-arm64
	$(call log_info,Building pitrac for arm64...)
	@PITRAC_REPO=$(PITRAC_REPO) PITRAC_BRANCH=$(PITRAC_BRANCH) ./scripts/build-package.sh pitrac arm64 $(PITRAC_VERSION)
	$(call log_success,pitrac built for arm64)

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
	@echo "Exporting APT repository metadata..."
	@reprepro export bookworm
	@echo "Export complete."

apt-update: apt-export apt-clean 
	@echo "APT repository updated."