import pytest
from pathlib import Path
from tests.conftest import PACKAGES
from tests.utils import PackageInspector

def test_lgpio_runtime_has_shared_libraries(project_root, distro):
    """Verify liblgpio1 contains .so.* files in correct location"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    runtime_debs = list(deb_dir.glob('liblgpio1_*.deb'))
    if not runtime_debs:
        pytest.skip("liblgpio1 not built")

    inspector = PackageInspector(runtime_debs[0])
    contents = inspector.get_package_contents()

    # Must contain shared library
    so_files = [f for f in contents if '.so.' in f and 'usr/lib' in f]
    assert len(so_files) > 0, "Runtime package must contain .so.* files"

    # Must be in correct multiarch directory
    correct_location = any('aarch64-linux-gnu' in f for f in so_files)
    assert correct_location, "Libraries must be in /usr/lib/aarch64-linux-gnu/"

def test_opencv_runtime_has_only_shared_libraries(project_root, distro):
    """Verify libopencv4.11 contains only .so.* files, not headers"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    runtime_debs = list(deb_dir.glob('libopencv4.11_*.deb'))
    if not runtime_debs:
        pytest.skip("libopencv4.11 not built")

    inspector = PackageInspector(runtime_debs[0])
    contents = inspector.get_package_contents()

    # Must have shared libraries
    so_files = [f for f in contents if '.so.' in f]
    assert len(so_files) > 0, "Runtime must contain shared libraries"

    # Must NOT have headers
    headers = [f for f in contents if f.endswith('.h') or f.endswith('.hpp')]
    assert len(headers) == 0, "Runtime package should not contain headers"

    # Must NOT have .so symlinks (those are for dev)
    so_links = [f for f in contents if f.endswith('.so') and '.so.' not in f]
    assert len(so_links) == 0, "Runtime should not contain .so symlinks"
