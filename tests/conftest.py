import os
import pytest
from pathlib import Path

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent

# Supported distributions and architectures
DISTRIBUTIONS = ['bookworm', 'trixie']
ARCHITECTURES = ['arm64']

# Package definitions with version matrix
PACKAGES = {
    'lgpio': {
        'version': '0.2.2-1',
        'debs': ['liblgpio1', 'liblgpio-dev'],
        'dockerfile': 'docker/Dockerfile.lgpio',
        'distro_versions': {'bookworm': '0.2.2-1', 'trixie': '0.2.2-1'}
    },
    'msgpack': {
        'version': '6.1.1-1',
        'debs': ['libmsgpack-cxx-dev'],
        'dockerfile': 'docker/Dockerfile.msgpack',
        'distro_versions': {'bookworm': '6.1.1-1', 'trixie': '6.1.1-1'}
    },
    'activemq': {
        'version': '3.9.5-1',
        'debs': ['libactivemq-cpp', 'libactivemq-cpp-dev'],
        'dockerfile': 'docker/Dockerfile.activemq',
        'distro_versions': {'bookworm': '3.9.5-1', 'trixie': '3.9.5-1'}
    },
    'opencv': {
        'version': '4.11.0-1',
        'debs': ['libopencv4.11', 'libopencv-dev'],
        'dockerfile': 'docker/Dockerfile.opencv',
        'distro_versions': {'bookworm': '4.11.0-1', 'trixie': '4.11.0-1'}
    },
    'onnxruntime': {
        'version': None,  # Version varies by distro
        'debs': ['libonnxruntime1.17.3', 'libonnxruntime-dev'],
        'dockerfile': 'docker/Dockerfile.onnxruntime',
        'distro_versions': {'bookworm': '1.17.3-xnnpack-verified', 'trixie': '1.22.1-1'}
    },
    'pitrac': {
        'version': None,  # Date-based version
        'debs': ['pitrac'],
        'dockerfile': 'docker/Dockerfile.pitrac',
        'distro_versions': None  # Dynamic, date-based
    }
}

@pytest.fixture(scope='session')
def project_root():
    """Return project root directory"""
    return PROJECT_ROOT

@pytest.fixture(params=DISTRIBUTIONS)
def distro(request):
    """Parametrize tests across distributions"""
    return request.param

@pytest.fixture(params=ARCHITECTURES)
def arch(request):
    """Parametrize tests across architectures"""
    return request.param

@pytest.fixture
def deb_output_dir(project_root, distro, arch):
    """Return DEB output directory for given distro/arch"""
    return project_root / 'build' / 'debs' / distro / arch
