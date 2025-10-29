import pytest
from pathlib import Path
from tests.utils.package_inspector import PackageInspector

def test_package_inspector_with_real_deb(project_root):
    """Test extraction with real DEB if available"""
    inspector = PackageInspector()

    # Look for any existing DEB in build output
    deb_dir = project_root / 'build' / 'debs'
    if not deb_dir.exists():
        pytest.skip("No built packages found - run 'make build-all' first")

    # Find first available DEB
    deb_files = list(deb_dir.rglob('*.deb'))
    if not deb_files:
        pytest.skip("No DEB files found")

    deb_path = deb_files[0]
    fields = inspector.get_control_fields(deb_path)

    # Verify required fields exist
    assert 'Package' in fields
    assert 'Version' in fields
    assert 'Architecture' in fields
    assert 'Maintainer' in fields
    assert fields['Architecture'] == 'arm64'

    # Test file listing
    contents = inspector.get_package_contents(deb_path)
    assert len(contents) > 0

    # Test size retrieval
    size = inspector.get_package_size(deb_path)
    assert size > 0
