import pytest
from pathlib import Path
from tests.conftest import PACKAGES
from tests.utils import PackageInspector

@pytest.mark.parametrize('package_name,package_info', PACKAGES.items())
def test_package_metadata_complete(project_root, distro, package_name, package_info):
    """Verify all packages have complete metadata"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    # Get expected version for this distro
    if package_info['distro_versions']:
        expected_version = package_info['distro_versions'][distro]
    elif package_name == 'pitrac':
        expected_version = None  # Date-based, skip version check
    else:
        expected_version = package_info['version']

    # Check each expected DEB
    found_any = False
    for deb_name in package_info['debs']:
        # Find DEB file (distro name not in filename, just version and arch)
        deb_pattern = f"{deb_name}_*.deb"
        deb_files = list(deb_dir.glob(deb_pattern))

        if not deb_files:
            # Skip this specific DEB, but continue checking others
            continue

        found_any = True

        deb_file = deb_files[0]
        inspector = PackageInspector(deb_file)

        # Verify control fields
        fields = inspector.get_control_fields()

        assert 'Package' in fields, "Missing Package field"
        assert fields['Package'] == deb_name, f"Package name mismatch: {fields['Package']} != {deb_name}"

        assert 'Version' in fields, "Missing Version field"
        if expected_version:
            assert fields['Version'] == expected_version, \
                f"Version mismatch for {deb_name}: {fields['Version']} != {expected_version}"

        assert 'Architecture' in fields, "Missing Architecture field"
        # Accept both 'arm64' and 'all' (architecture-independent packages)
        assert fields['Architecture'] in ['arm64', 'all'], \
            f"Architecture should be arm64 or all, got {fields['Architecture']}"

        assert 'Maintainer' in fields, "Missing Maintainer field"
        assert 'PiTrac' in fields['Maintainer'], "Maintainer should be PiTrac Build System"

        assert 'Description' in fields, "Missing Description field"
        assert len(fields['Description']) > 10, "Description too short"

        assert 'Section' in fields, "Missing Section field"

    # Skip test if no DEBs were found at all
    if not found_any:
        pytest.skip(f"No packages built for {package_name} in {distro}")

def test_lgpio_dev_depends_on_runtime(project_root, distro):
    """Verify liblgpio-dev depends on liblgpio1"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    dev_debs = list(deb_dir.glob('liblgpio-dev_*.deb'))
    if not dev_debs:
        pytest.skip("liblgpio-dev not built")

    inspector = PackageInspector(dev_debs[0])
    deps = inspector.get_dependencies()

    # Dev package must depend on runtime package
    assert len(deps['depends']) > 0, "liblgpio-dev should have dependencies"

    runtime_dep_found = any('liblgpio1' in dep for dep in deps['depends'])
    assert runtime_dep_found, "liblgpio-dev must depend on liblgpio1"

def test_opencv_dev_depends_on_runtime(project_root, distro):
    """Verify libopencv-dev depends on libopencv4.11"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    dev_debs = list(deb_dir.glob('libopencv-dev_*.deb'))
    if not dev_debs:
        pytest.skip("libopencv-dev not built")

    inspector = PackageInspector(dev_debs[0])
    deps = inspector.get_dependencies()

    runtime_dep_found = any('libopencv4.11' in dep for dep in deps['depends'])
    assert runtime_dep_found, "libopencv-dev must depend on libopencv4.11"

def test_pitrac_has_all_dependencies(project_root, distro):
    """Verify pitrac package declares all required dependencies"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    pitrac_debs = list(deb_dir.glob('pitrac_*.deb'))
    if not pitrac_debs:
        pytest.skip("pitrac not built")

    inspector = PackageInspector(pitrac_debs[0])
    deps = inspector.get_dependencies()

    required_deps = [
        'liblgpio',
        'libmsgpack',
        'libactivemq-cpp',
        'libopencv',
        'libonnxruntime'
    ]

    for required in required_deps:
        dep_found = any(required in dep for dep in deps['depends'])
        assert dep_found, f"pitrac must depend on {required}"
