#!/bin/bash
# Add all repacked packages to repository

set -e

cd /home/cgallopo/dev/pitrac/packages

echo "Adding Bookworm packages..."
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libactivemq-cpp_3.9.5-1~bookworm1_arm64.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libactivemq-cpp-dev_3.9.5-1~bookworm1_arm64.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/liblgpio1_0.2.2-1~bookworm1_arm64.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libmsgpack-cxx-dev_6.1.1-1~bookworm1_all.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libonnxruntime1.17.3_1.17.3-xnnpack-verified~bookworm1_arm64.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libopencv4.11_4.11.0-1~bookworm1_arm64.deb
reprepro -b build/repo includedeb bookworm build/debs-repacked/bookworm/arm64/libopencv-dev_4.11.0-1~bookworm1_arm64.deb

echo "Adding Trixie packages..."
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libactivemq-cpp_3.9.5-1~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libactivemq-cpp-dev_3.9.5-1~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/liblgpio1_0.2.2-1~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/liblgpio-dev_0.2.2-1~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libmsgpack-cxx-dev_6.1.1-1~trixie1_all.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libonnxruntime1.22.1_1.22.1-xnnpack3~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libopencv4.11_4.11.0-1~trixie1_arm64.deb
reprepro -b build/repo includedeb trixie build/debs-repacked/trixie/arm64/libopencv-dev_4.11.0-1~trixie1_arm64.deb

echo "Done!"
