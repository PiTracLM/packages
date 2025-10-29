import pytest
from tests.utils.docker_builder import DockerBuilder

def test_dockerfile_exists():
    """Test that Dockerfile validation works"""
    builder = DockerBuilder()
    assert builder.dockerfile_exists('docker/Dockerfile.lgpio')
    assert not builder.dockerfile_exists('docker/Dockerfile.nonexistent')

def test_parse_dockerfile_args():
    """Test extraction of build args from Dockerfile"""
    builder = DockerBuilder()
    args = builder.get_required_build_args('docker/Dockerfile.lgpio')
    assert 'PACKAGE_VERSION' in args
    assert 'DEBIAN_ARCH' in args
    assert 'DEBIAN_DISTRO' in args
