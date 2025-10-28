# DEB Package Validation Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a comprehensive testing framework to validate that all DEB creation scripts and Dockerfiles produce packages with correct metadata, dependencies, and functionality across both Bookworm and Trixie distributions.

**Architecture:** Python-based test framework using pytest with fixtures for package validation, dpkg utilities for metadata inspection, Docker for build verification, and APT repository testing in isolated containers. Tests are organized by package type with shared utilities for common validations.

**Tech Stack:** Python 3.11+, pytest, pytest-xdist (parallel execution), Docker Python SDK, dpkg-deb, lintian, piuparts (Debian package testing tool)

---

## Task 1: Create Test Framework Structure

**Files:**
- Create: `tests/conftest.py`
- Create: `tests/__init__.py`
- Create: `tests/requirements.txt`
- Create: `tests/utils/__init__.py`
- Create: `tests/utils/package_inspector.py`
- Create: `tests/utils/docker_builder.py`
- Create: `tests/utils/apt_validator.py`

**Step 1: Write the project structure setup test**

```python
# tests/test_structure.py
def test_project_structure_exists():
    """Verify required directories exist"""
    import os
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    required_dirs = [
        'docker',
        'scripts',
        'conf',
        'tests/utils'
    ]
    for dir_path in required_dirs:
        full_path = os.path.join(project_root, dir_path)
        assert os.path.isdir(full_path), f"Required directory {dir_path} does not exist"
```

**Step 2: Run test to verify it passes (structure already exists)**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_structure.py -v`
Expected: PASS

**Step 3: Create test requirements file**

```python
# tests/requirements.txt
pytest>=7.4.0
pytest-xdist>=3.5.0
pytest-timeout>=2.2.0
docker>=7.0.0
pyyaml>=6.0
```

**Step 4: Install test dependencies**

Run: `cd /home/cgallopo/dev/pitrac/packages && pip3 install -r tests/requirements.txt`
Expected: All packages installed successfully

**Step 5: Create pytest configuration**

```python
# tests/conftest.py
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
        'distro_versions': {'bookworm': '1.17.3-1', 'trixie': '1.22.1-1'}
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
```

**Step 6: Run configuration test**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -c "from tests.conftest import *; print('Config loaded')"`
Expected: "Config loaded" printed

**Step 7: Commit test framework structure**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/conftest.py tests/__init__.py tests/requirements.txt tests/test_structure.py
git commit -m "feat: add test framework structure for DEB validation

- Create pytest configuration with distro/arch parametrization
- Add project structure validation test
- Define package metadata matrix for all packages
- Set up test requirements

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Package Inspector Utility

**Files:**
- Create: `tests/utils/package_inspector.py`

**Step 1: Write test for package metadata extraction**

```python
# tests/test_package_inspector.py
import pytest
from pathlib import Path
from tests.utils.package_inspector import PackageInspector

def test_extract_control_fields():
    """Test extraction of control file fields from a DEB"""
    # This will fail until we implement the inspector
    inspector = PackageInspector()
    fields = inspector.get_control_fields('/nonexistent.deb')
    assert 'Package' in fields
    assert 'Version' in fields
    assert 'Architecture' in fields
```

**Step 2: Run test to verify it fails**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_inspector.py::test_extract_control_fields -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'tests.utils.package_inspector'"

**Step 3: Implement PackageInspector class**

```python
# tests/utils/package_inspector.py
"""
Utilities for inspecting Debian package metadata and contents.
"""
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Optional

class PackageInspector:
    """Inspector for Debian package files"""

    def __init__(self, deb_path: Optional[Path] = None):
        """
        Initialize inspector with optional package path.

        Args:
            deb_path: Path to .deb file to inspect
        """
        self.deb_path = Path(deb_path) if deb_path else None

    def get_control_fields(self, deb_path: Optional[Path] = None) -> Dict[str, str]:
        """
        Extract control file fields from a DEB package.

        Args:
            deb_path: Path to .deb file (overrides instance path)

        Returns:
            Dictionary of control file fields

        Raises:
            FileNotFoundError: If DEB file doesn't exist
            subprocess.CalledProcessError: If dpkg-deb fails
        """
        path = Path(deb_path) if deb_path else self.deb_path
        if not path or not path.exists():
            raise FileNotFoundError(f"DEB file not found: {path}")

        # Use dpkg-deb to extract control information
        result = subprocess.run(
            ['dpkg-deb', '-f', str(path)],
            capture_output=True,
            text=True,
            check=True
        )

        # Parse control fields
        fields = {}
        for line in result.stdout.strip().split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                fields[key.strip()] = value.strip()

        return fields

    def get_package_contents(self, deb_path: Optional[Path] = None) -> List[str]:
        """
        List all files contained in a DEB package.

        Args:
            deb_path: Path to .deb file (overrides instance path)

        Returns:
            List of file paths within the package
        """
        path = Path(deb_path) if deb_path else self.deb_path
        if not path or not path.exists():
            raise FileNotFoundError(f"DEB file not found: {path}")

        result = subprocess.run(
            ['dpkg-deb', '-c', str(path)],
            capture_output=True,
            text=True,
            check=True
        )

        # Extract file paths from dpkg-deb output
        files = []
        for line in result.stdout.strip().split('\n'):
            # dpkg-deb -c output format: permissions user/group size date time ./path
            match = re.search(r'\s+(\./\S+)$', line)
            if match:
                files.append(match.group(1))

        return files

    def get_dependencies(self, deb_path: Optional[Path] = None) -> Dict[str, List[str]]:
        """
        Extract dependency information from package.

        Args:
            deb_path: Path to .deb file (overrides instance path)

        Returns:
            Dictionary with 'depends', 'recommends', 'suggests' lists
        """
        fields = self.get_control_fields(deb_path)

        deps = {
            'depends': [],
            'recommends': [],
            'suggests': [],
            'conflicts': [],
            'replaces': [],
            'provides': []
        }

        for key in deps.keys():
            field_name = key.capitalize()
            if field_name in fields:
                # Split by comma and strip whitespace
                deps[key] = [dep.strip() for dep in fields[field_name].split(',')]

        return deps

    def verify_architecture(self, deb_path: Optional[Path] = None, expected_arch: str = 'arm64') -> bool:
        """
        Verify package architecture matches expected.

        Args:
            deb_path: Path to .deb file (overrides instance path)
            expected_arch: Expected architecture (default: arm64)

        Returns:
            True if architecture matches
        """
        fields = self.get_control_fields(deb_path)
        return fields.get('Architecture') == expected_arch

    def verify_version(self, deb_path: Optional[Path] = None, expected_version: str = None) -> bool:
        """
        Verify package version matches expected.

        Args:
            deb_path: Path to .deb file (overrides instance path)
            expected_version: Expected version string

        Returns:
            True if version matches
        """
        if not expected_version:
            return True

        fields = self.get_control_fields(deb_path)
        return fields.get('Version') == expected_version

    def get_package_size(self, deb_path: Optional[Path] = None) -> int:
        """
        Get package file size in bytes.

        Args:
            deb_path: Path to .deb file (overrides instance path)

        Returns:
            File size in bytes
        """
        path = Path(deb_path) if deb_path else self.deb_path
        if not path or not path.exists():
            raise FileNotFoundError(f"DEB file not found: {path}")

        return path.stat().st_size
```

**Step 4: Update __init__ file**

```python
# tests/utils/__init__.py
from .package_inspector import PackageInspector

__all__ = ['PackageInspector']
```

**Step 5: Run test with mock DEB (still fails, need real DEB)**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_inspector.py::test_extract_control_fields -v`
Expected: FAIL with "FileNotFoundError: DEB file not found"

**Step 6: Update test to use existing DEB if available**

```python
# tests/test_package_inspector.py
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
```

**Step 7: Run updated test**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_inspector.py -v`
Expected: SKIP if no DEBs exist, or PASS if DEBs are present

**Step 8: Commit package inspector utility**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/utils/package_inspector.py tests/utils/__init__.py tests/test_package_inspector.py
git commit -m "feat: add package inspector utility for DEB validation

- Implement PackageInspector class with dpkg-deb wrapper
- Extract control fields, dependencies, file contents
- Verify architecture and version information
- Add tests with real DEB package validation

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Docker Builder Utility

**Files:**
- Create: `tests/utils/docker_builder.py`

**Step 1: Write test for Docker build verification**

```python
# tests/test_docker_builder.py
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
```

**Step 2: Run test to verify it fails**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_docker_builder.py -v`
Expected: FAIL with "ModuleNotFoundError"

**Step 3: Implement DockerBuilder class**

```python
# tests/utils/docker_builder.py
"""
Utilities for building and testing Docker-based package builds.
"""
import docker
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class DockerBuilder:
    """Helper for Docker-based package building"""

    def __init__(self, project_root: Optional[Path] = None):
        """
        Initialize Docker builder.

        Args:
            project_root: Root directory of project (defaults to auto-detect)
        """
        if project_root:
            self.project_root = Path(project_root)
        else:
            # Auto-detect project root (directory containing docker/ and scripts/)
            current = Path(__file__).parent
            while current != current.parent:
                if (current / 'docker').is_dir() and (current / 'scripts').is_dir():
                    self.project_root = current
                    break
                current = current.parent
            else:
                raise RuntimeError("Could not find project root")

        self.docker_client = docker.from_env()

    def dockerfile_exists(self, dockerfile_path: str) -> bool:
        """
        Check if Dockerfile exists.

        Args:
            dockerfile_path: Relative path to Dockerfile from project root

        Returns:
            True if file exists
        """
        full_path = self.project_root / dockerfile_path
        return full_path.exists() and full_path.is_file()

    def get_required_build_args(self, dockerfile_path: str) -> List[str]:
        """
        Extract required ARG declarations from Dockerfile.

        Args:
            dockerfile_path: Relative path to Dockerfile from project root

        Returns:
            List of ARG names declared in Dockerfile
        """
        full_path = self.project_root / dockerfile_path
        if not full_path.exists():
            raise FileNotFoundError(f"Dockerfile not found: {dockerfile_path}")

        args = []
        with open(full_path, 'r') as f:
            for line in f:
                # Match ARG declarations (ARG NAME or ARG NAME=default)
                match = re.match(r'^ARG\s+(\w+)', line.strip())
                if match:
                    args.append(match.group(1))

        return args

    def build_image(
        self,
        dockerfile_path: str,
        tag: str,
        build_args: Optional[Dict[str, str]] = None,
        platform: str = 'linux/arm64'
    ) -> Tuple[bool, str]:
        """
        Build Docker image from Dockerfile.

        Args:
            dockerfile_path: Relative path to Dockerfile from project root
            tag: Image tag to use
            build_args: Dictionary of build arguments
            platform: Target platform (default: linux/arm64)

        Returns:
            Tuple of (success: bool, output: str)
        """
        full_dockerfile = self.project_root / dockerfile_path
        if not full_dockerfile.exists():
            return False, f"Dockerfile not found: {dockerfile_path}"

        try:
            # Build using subprocess for better output control
            cmd = [
                'docker', 'build',
                '--platform', platform,
                '-f', str(full_dockerfile),
                '-t', tag
            ]

            # Add build arguments
            if build_args:
                for key, value in build_args.items():
                    cmd.extend(['--build-arg', f'{key}={value}'])

            cmd.append(str(self.project_root))

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=3600  # 1 hour timeout
            )

            return result.returncode == 0, result.stdout + result.stderr

        except subprocess.TimeoutExpired:
            return False, "Build timeout (>1 hour)"
        except Exception as e:
            return False, str(e)

    def extract_debs_from_image(
        self,
        image_tag: str,
        output_dir: Path,
        platform: str = 'linux/arm64'
    ) -> List[Path]:
        """
        Extract .deb files from built Docker image.

        Args:
            image_tag: Tag of built image
            tag: Image tag to use
            output_dir: Directory to extract DEBs to
            platform: Platform used for image

        Returns:
            List of extracted DEB file paths
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        try:
            # Create container from image
            container = self.docker_client.containers.create(
                image_tag,
                platform=platform
            )

            extracted_debs = []

            try:
                # Try to copy from /output first
                bits, stat = container.get_archive('/output/')
                import tarfile
                import io

                tar_stream = io.BytesIO()
                for chunk in bits:
                    tar_stream.write(chunk)
                tar_stream.seek(0)

                with tarfile.open(fileobj=tar_stream) as tar:
                    for member in tar.getmembers():
                        if member.name.endswith('.deb'):
                            tar.extract(member, path=output_dir)
                            extracted_debs.append(output_dir / member.name)

            except docker.errors.NotFound:
                # Try /build directory instead
                bits, stat = container.get_archive('/build/')
                import tarfile
                import io

                tar_stream = io.BytesIO()
                for chunk in bits:
                    tar_stream.write(chunk)
                tar_stream.seek(0)

                with tarfile.open(fileobj=tar_stream) as tar:
                    for member in tar.getmembers():
                        if member.name.endswith('.deb'):
                            tar.extract(member, path=output_dir)
                            extracted_debs.append(output_dir / member.name)

            finally:
                # Clean up container
                container.remove()

            return extracted_debs

        except Exception as e:
            raise RuntimeError(f"Failed to extract DEBs: {e}")

    def verify_build_script(self, package_name: str) -> Tuple[bool, str]:
        """
        Verify build-package.sh script can handle package.

        Args:
            package_name: Name of package to verify

        Returns:
            Tuple of (valid: bool, message: str)
        """
        script_path = self.project_root / 'scripts' / 'build-package.sh'
        if not script_path.exists():
            return False, "build-package.sh not found"

        # Check if package is in the case statement
        with open(script_path, 'r') as f:
            content = f.read()

        # Look for package name in case statement
        pattern = rf'{package_name}\|'
        if re.search(pattern, content):
            return True, f"Package {package_name} is supported"

        return False, f"Package {package_name} not found in build script"
```

**Step 4: Update utils __init__**

```python
# tests/utils/__init__.py
from .package_inspector import PackageInspector
from .docker_builder import DockerBuilder

__all__ = ['PackageInspector', 'DockerBuilder']
```

**Step 5: Run Docker builder tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_docker_builder.py -v`
Expected: PASS for dockerfile_exists and parse tests

**Step 6: Commit Docker builder utility**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/utils/docker_builder.py tests/test_docker_builder.py tests/utils/__init__.py
git commit -m "feat: add Docker builder utility for build verification

- Implement DockerBuilder class with docker Python SDK
- Parse Dockerfile ARG declarations
- Build images and extract DEB files
- Verify build script package support

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: APT Repository Validator

**Files:**
- Create: `tests/utils/apt_validator.py`

**Step 1: Write test for APT repository validation**

```python
# tests/test_apt_validator.py
import pytest
from tests.utils.apt_validator import AptValidator

def test_distributions_file_exists(project_root):
    """Test that conf/distributions exists and is valid"""
    validator = AptValidator(project_root)
    assert validator.distributions_file_exists()

def test_parse_distributions(project_root):
    """Test parsing of distributions configuration"""
    validator = AptValidator(project_root)
    distros = validator.get_configured_distributions()
    assert 'bookworm' in distros
    assert 'trixie' in distros
    assert distros['bookworm']['Architectures'] == 'arm64'
    assert distros['trixie']['Architectures'] == 'arm64'
```

**Step 2: Run test to verify it fails**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_apt_validator.py -v`
Expected: FAIL with "ModuleNotFoundError"

**Step 3: Implement AptValidator class**

```python
# tests/utils/apt_validator.py
"""
Utilities for validating APT repository structure and configuration.
"""
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

class AptValidator:
    """Validator for APT repository structure"""

    def __init__(self, project_root: Path):
        """
        Initialize APT validator.

        Args:
            project_root: Root directory of package repository
        """
        self.project_root = Path(project_root)
        self.conf_dir = self.project_root / 'conf'
        self.distributions_file = self.conf_dir / 'distributions'

    def distributions_file_exists(self) -> bool:
        """
        Check if conf/distributions exists.

        Returns:
            True if file exists
        """
        return self.distributions_file.exists()

    def get_configured_distributions(self) -> Dict[str, Dict[str, str]]:
        """
        Parse conf/distributions file.

        Returns:
            Dictionary mapping codename to distribution configuration
        """
        if not self.distributions_file.exists():
            raise FileNotFoundError("conf/distributions not found")

        distros = {}
        current_distro = {}
        current_codename = None

        with open(self.distributions_file, 'r') as f:
            for line in f:
                line = line.strip()

                # Skip empty lines (end of distribution block)
                if not line:
                    if current_codename and current_distro:
                        distros[current_codename] = current_distro
                        current_distro = {}
                        current_codename = None
                    continue

                # Parse key: value pairs
                if ':' in line:
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip()
                    current_distro[key] = value

                    if key == 'Codename':
                        current_codename = value

        # Add last distribution if not followed by blank line
        if current_codename and current_distro:
            distros[current_codename] = current_distro

        return distros

    def verify_repository_structure(self) -> List[str]:
        """
        Verify required APT repository directories exist.

        Returns:
            List of missing directories (empty if all exist)
        """
        required_dirs = [
            'conf',
            'dists',
            'pool'
        ]

        missing = []
        for dir_name in required_dirs:
            dir_path = self.project_root / dir_name
            if not dir_path.exists():
                missing.append(dir_name)

        return missing

    def get_packages_in_pool(self) -> List[Path]:
        """
        List all .deb packages in pool directory.

        Returns:
            List of paths to .deb files
        """
        pool_dir = self.project_root / 'pool'
        if not pool_dir.exists():
            return []

        return list(pool_dir.rglob('*.deb'))

    def verify_package_in_repository(
        self,
        package_name: str,
        distro: str,
        component: str = 'main'
    ) -> bool:
        """
        Verify a package is registered in the repository.

        Args:
            package_name: Name of package to check
            distro: Distribution codename (bookworm, trixie)
            component: Component name (main, contrib, non-free)

        Returns:
            True if package is in repository
        """
        packages_file = (
            self.project_root / 'dists' / distro / component /
            'binary-arm64' / 'Packages'
        )

        if not packages_file.exists():
            return False

        with open(packages_file, 'r') as f:
            content = f.read()

        # Look for "Package: <name>" in Packages file
        pattern = rf'^Package:\s+{re.escape(package_name)}$'
        return bool(re.search(pattern, content, re.MULTILINE))

    def get_package_list(self, distro: str, component: str = 'main') -> List[str]:
        """
        Get list of packages in repository for distribution.

        Args:
            distro: Distribution codename
            component: Component name

        Returns:
            List of package names
        """
        packages_file = (
            self.project_root / 'dists' / distro / component /
            'binary-arm64' / 'Packages'
        )

        if not packages_file.exists():
            return []

        packages = []
        with open(packages_file, 'r') as f:
            for line in f:
                if line.startswith('Package:'):
                    package_name = line.split(':', 1)[1].strip()
                    packages.append(package_name)

        return packages

    def verify_gpg_signature(self, distro: str) -> Tuple[bool, str]:
        """
        Verify GPG signature on Release file.

        Args:
            distro: Distribution codename

        Returns:
            Tuple of (valid: bool, message: str)
        """
        release_file = self.project_root / 'dists' / distro / 'Release'
        release_gpg = self.project_root / 'dists' / distro / 'Release.gpg'

        if not release_file.exists():
            return False, f"Release file not found for {distro}"

        if not release_gpg.exists():
            return False, f"Release.gpg not found for {distro}"

        try:
            result = subprocess.run(
                ['gpg', '--verify', str(release_gpg), str(release_file)],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                return True, "GPG signature valid"
            else:
                return False, f"GPG verification failed: {result.stderr}"

        except FileNotFoundError:
            return False, "gpg command not found"
        except Exception as e:
            return False, f"Verification error: {e}"
```

**Step 4: Add missing import to apt_validator**

```python
# tests/utils/apt_validator.py (add to imports at top)
from typing import Dict, List, Optional, Tuple
```

**Step 5: Update utils __init__**

```python
# tests/utils/__init__.py
from .package_inspector import PackageInspector
from .docker_builder import DockerBuilder
from .apt_validator import AptValidator

__all__ = ['PackageInspector', 'DockerBuilder', 'AptValidator']
```

**Step 6: Run APT validator tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_apt_validator.py -v`
Expected: PASS for distribution parsing tests

**Step 7: Commit APT validator utility**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/utils/apt_validator.py tests/test_apt_validator.py tests/utils/__init__.py
git commit -m "feat: add APT repository validator utility

- Implement AptValidator for repository structure checking
- Parse conf/distributions configuration
- Verify package inclusion in repository
- Check GPG signatures on Release files

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Package Metadata Tests

**Files:**
- Create: `tests/test_package_metadata.py`

**Step 1: Write test for lgpio metadata**

```python
# tests/test_package_metadata.py
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
    for deb_name in package_info['debs']:
        # Find DEB file
        deb_pattern = f"{deb_name}_*_{distro}*.deb" if expected_version else f"{deb_name}_*.deb"
        deb_files = list(deb_dir.glob(deb_pattern))

        if not deb_files:
            pytest.skip(f"Package {deb_name} not built for {distro}")

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
        assert fields['Architecture'] == 'arm64', "Architecture should be arm64"

        assert 'Maintainer' in fields, "Missing Maintainer field"
        assert 'PiTrac' in fields['Maintainer'], "Maintainer should be PiTrac Build System"

        assert 'Description' in fields, "Missing Description field"
        assert len(fields['Description']) > 10, "Description too short"

        assert 'Section' in fields, "Missing Section field"
```

**Step 2: Run metadata tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_metadata.py -v`
Expected: SKIP if no packages built, PASS if packages exist

**Step 3: Write test for dependency declarations**

```python
# tests/test_package_metadata.py (add to file)

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
```

**Step 4: Run dependency tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_metadata.py::test_lgpio_dev_depends_on_runtime -v`
Expected: SKIP or PASS depending on package availability

**Step 5: Commit metadata tests**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/test_package_metadata.py
git commit -m "feat: add package metadata validation tests

- Verify all control fields are present and valid
- Check architecture is arm64 for all packages
- Verify version matches expected per distribution
- Test dependency relationships (dev depends on runtime)
- Validate pitrac has all required dependencies

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Package Content Tests

**Files:**
- Create: `tests/test_package_contents.py`

**Step 1: Write test for library file locations**

```python
# tests/test_package_contents.py
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

def test_lgpio_dev_has_headers_and_static_libs(project_root, distro):
    """Verify liblgpio-dev contains headers and development files"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    dev_debs = list(deb_dir.glob('liblgpio-dev_*.deb'))
    if not dev_debs:
        pytest.skip("liblgpio-dev not built")

    inspector = PackageInspector(dev_debs[0])
    contents = inspector.get_package_contents()

    # Must contain headers
    headers = [f for f in contents if f.endswith('.h') and 'usr/include' in f]
    assert len(headers) > 0, "Dev package must contain header files"

    # Must contain symlink .so files (without version)
    so_links = [f for f in contents if f.endswith('.so') and 'usr/lib' in f]
    assert len(so_links) > 0, "Dev package must contain .so symlinks"

    # Should contain pkg-config file
    pc_files = [f for f in contents if f.endswith('.pc') and 'pkgconfig' in f]
    assert len(pc_files) > 0, "Dev package should contain .pc file"

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

def test_opencv_dev_has_headers_and_pkgconfig(project_root, distro):
    """Verify libopencv-dev contains headers and pkg-config"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    dev_debs = list(deb_dir.glob('libopencv-dev_*.deb'))
    if not dev_debs:
        pytest.skip("libopencv-dev not built")

    inspector = PackageInspector(dev_debs[0])
    contents = inspector.get_package_contents()

    # Must have C++ headers
    headers = [f for f in contents if f.endswith('.hpp') and 'usr/include' in f]
    assert len(headers) > 0, "Dev package must contain .hpp headers"

    # Must have pkg-config file
    pc_files = [f for f in contents if f.endswith('.pc') and 'pkgconfig' in f]
    assert len(pc_files) > 0, "Dev package must contain opencv4.pc"

    # Must have .so symlinks
    so_links = [f for f in contents if f.endswith('.so') and '.so.' not in f]
    assert len(so_links) > 0, "Dev package must contain .so symlinks"

def test_pitrac_binary_is_executable(project_root, distro):
    """Verify pitrac package contains executable binary"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    pitrac_debs = list(deb_dir.glob('pitrac_*.deb'))
    if not pitrac_debs:
        pytest.skip("pitrac not built")

    inspector = PackageInspector(pitrac_debs[0])
    contents = inspector.get_package_contents()

    # Should contain binary in /usr/bin or /usr/local/bin
    binaries = [f for f in contents if 'bin/pitrac' in f or 'bin/PiTrac' in f]
    assert len(binaries) > 0, "pitrac package must contain executable binary"
```

**Step 2: Run content tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_contents.py -v`
Expected: SKIP or PASS depending on package availability

**Step 3: Write test for file permissions**

```python
# tests/test_package_contents.py (add to file)

def test_shared_libraries_have_correct_permissions(project_root, distro):
    """Verify shared libraries have 0644 or 0755 permissions"""
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'

    if not deb_dir.exists():
        pytest.skip(f"No packages built for {distro}/arm64")

    # Check all runtime library packages
    runtime_patterns = ['liblgpio1_*.deb', 'libopencv4.11_*.deb', 'libactivemq-cpp_*.deb']

    for pattern in runtime_patterns:
        debs = list(deb_dir.glob(pattern))
        if not debs:
            continue

        inspector = PackageInspector(debs[0])

        # Extract actual package to check permissions
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            # Extract package contents
            subprocess.run(
                ['dpkg-deb', '-x', str(debs[0]), tmpdir],
                check=True,
                capture_output=True
            )

            # Check .so file permissions
            import os
            for root, dirs, files in os.walk(tmpdir):
                for file in files:
                    if '.so' in file:
                        filepath = os.path.join(root, file)
                        mode = os.stat(filepath).st_mode
                        # Should be readable by all
                        assert mode & 0o444, f"{file} should be readable"
```

**Step 4: Run permission tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_package_contents.py::test_shared_libraries_have_correct_permissions -v`
Expected: SKIP or PASS

**Step 5: Commit content tests**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/test_package_contents.py
git commit -m "feat: add package content validation tests

- Verify runtime packages contain only .so.* files
- Verify dev packages contain headers and .so symlinks
- Check pkg-config files are included
- Validate multiarch directory structure
- Test file permissions on libraries

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Build Process Tests

**Files:**
- Create: `tests/test_build_process.py`

**Step 1: Write test for Dockerfile ARG validation**

```python
# tests/test_build_process.py
import pytest
from tests.conftest import PACKAGES
from tests.utils import DockerBuilder

@pytest.mark.parametrize('package_name,package_info', PACKAGES.items())
def test_dockerfile_exists_for_package(project_root, package_name, package_info):
    """Verify Dockerfile exists for each package"""
    builder = DockerBuilder(project_root)
    dockerfile_path = package_info['dockerfile']

    assert builder.dockerfile_exists(dockerfile_path), \
        f"Dockerfile missing: {dockerfile_path}"

@pytest.mark.parametrize('package_name,package_info', PACKAGES.items())
def test_dockerfile_has_required_args(project_root, package_name, package_info):
    """Verify Dockerfile declares required ARGs"""
    builder = DockerBuilder(project_root)
    dockerfile_path = package_info['dockerfile']

    args = builder.get_required_build_args(dockerfile_path)

    # All Dockerfiles should have these args
    assert 'PACKAGE_VERSION' in args, "Missing PACKAGE_VERSION ARG"
    assert 'DEBIAN_ARCH' in args, "Missing DEBIAN_ARCH ARG"
    assert 'DEBIAN_DISTRO' in args, "Missing DEBIAN_DISTRO ARG"

def test_build_package_script_exists(project_root):
    """Verify build-package.sh script exists"""
    script_path = project_root / 'scripts' / 'build-package.sh'
    assert script_path.exists(), "build-package.sh not found"
    assert script_path.stat().st_mode & 0o111, "build-package.sh not executable"

@pytest.mark.parametrize('package_name', PACKAGES.keys())
def test_build_script_supports_package(project_root, package_name):
    """Verify build-package.sh recognizes each package"""
    builder = DockerBuilder(project_root)
    valid, message = builder.verify_build_script(package_name)

    assert valid, f"Package {package_name} not supported in build script: {message}"

@pytest.mark.parametrize('distro', ['bookworm', 'trixie'])
def test_makefile_has_distro_targets(project_root, distro):
    """Verify Makefile has targets for each distribution"""
    makefile = project_root / 'Makefile'
    assert makefile.exists(), "Makefile not found"

    with open(makefile, 'r') as f:
        content = f.read()

    # Check for build-all-<distro> target
    assert f'build-all-{distro}' in content, f"Missing build-all-{distro} target"

    # Check for package-specific targets
    for package in ['lgpio', 'opencv', 'onnxruntime']:
        target = f'build-{package}-{distro}'
        assert target in content, f"Missing {target} target"
```

**Step 2: Run build process tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_build_process.py -v`
Expected: PASS for all dockerfile and script tests

**Step 3: Write integration test for full build**

```python
# tests/test_build_process.py (add to file)

@pytest.mark.slow
@pytest.mark.parametrize('distro', ['bookworm'])  # Start with just bookworm
def test_lgpio_builds_successfully(project_root, distro):
    """Integration test: Build lgpio package from scratch"""
    import subprocess

    # Run make target
    result = subprocess.run(
        ['make', f'build-lgpio-{distro}'],
        cwd=project_root,
        capture_output=True,
        text=True,
        timeout=1800  # 30 minute timeout
    )

    assert result.returncode == 0, f"Build failed: {result.stderr}"

    # Verify output DEBs exist
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'
    runtime_deb = list(deb_dir.glob('liblgpio1_*.deb'))
    dev_deb = list(deb_dir.glob('liblgpio-dev_*.deb'))

    assert len(runtime_deb) > 0, "Runtime DEB not created"
    assert len(dev_deb) > 0, "Dev DEB not created"
```

**Step 4: Run build integration test (marked slow)**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_build_process.py::test_lgpio_builds_successfully -v -m slow`
Expected: PASS after ~10-15 minutes (actual build time)

**Step 5: Commit build process tests**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/test_build_process.py
git commit -m "feat: add build process validation tests

- Verify all Dockerfiles exist and have required ARGs
- Test build-package.sh recognizes all packages
- Validate Makefile targets for both distributions
- Add integration test for full lgpio build
- Mark slow tests with @pytest.mark.slow

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: APT Repository Tests

**Files:**
- Create: `tests/test_apt_repository.py`

**Step 1: Write test for repository structure**

```python
# tests/test_apt_repository.py
import pytest
from tests.utils import AptValidator

def test_repository_directories_exist(project_root):
    """Verify APT repository structure is complete"""
    validator = AptValidator(project_root)
    missing = validator.verify_repository_structure()

    assert len(missing) == 0, f"Missing repository directories: {missing}"

def test_distributions_config_valid(project_root):
    """Verify conf/distributions is valid"""
    validator = AptValidator(project_root)

    assert validator.distributions_file_exists(), "conf/distributions not found"

    distros = validator.get_configured_distributions()

    assert 'bookworm' in distros, "bookworm not configured"
    assert 'trixie' in distros, "trixie not configured"

    # Verify bookworm config
    bookworm = distros['bookworm']
    assert bookworm['Architectures'] == 'arm64'
    assert bookworm['Components'] == 'main contrib non-free'
    assert 'SignWith' in bookworm

    # Verify trixie config
    trixie = distros['trixie']
    assert trixie['Architectures'] == 'arm64'
    assert trixie['Components'] == 'main contrib non-free'
    assert 'SignWith' in trixie

@pytest.mark.parametrize('distro', ['bookworm', 'trixie'])
def test_distribution_has_release_files(project_root, distro):
    """Verify Release files exist for distribution"""
    release_file = project_root / 'dists' / distro / 'Release'

    if not release_file.exists():
        pytest.skip(f"Repository not initialized for {distro}")

    # Verify Release file has required fields
    with open(release_file, 'r') as f:
        content = f.read()

    required_fields = ['Origin', 'Label', 'Suite', 'Codename', 'Architectures', 'Components']
    for field in required_fields:
        assert f'{field}:' in content, f"Missing {field} in Release file"

@pytest.mark.parametrize('distro', ['bookworm', 'trixie'])
def test_packages_file_exists(project_root, distro):
    """Verify Packages file exists for distribution"""
    packages_file = project_root / 'dists' / distro / 'main' / 'binary-arm64' / 'Packages'

    if not packages_file.exists():
        pytest.skip(f"No packages added to {distro} repository yet")

    # Verify it's not empty
    assert packages_file.stat().st_size > 0, "Packages file is empty"

def test_pool_directory_structure(project_root):
    """Verify pool directory contains packages"""
    validator = AptValidator(project_root)
    packages = validator.get_packages_in_pool()

    if len(packages) == 0:
        pytest.skip("No packages in pool yet")

    # Verify all packages are .deb files
    for pkg in packages:
        assert pkg.suffix == '.deb', f"Non-DEB file in pool: {pkg}"
        assert pkg.exists(), f"Package file missing: {pkg}"
```

**Step 2: Run repository structure tests**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_apt_repository.py -v`
Expected: PASS for structure tests, SKIP for some if repo not initialized

**Step 3: Write test for package installation**

```python
# tests/test_apt_repository.py (add to file)

@pytest.mark.integration
@pytest.mark.parametrize('distro', ['bookworm', 'trixie'])
def test_install_liblgpio_in_container(project_root, distro):
    """Integration test: Install liblgpio from repository in clean container"""
    import docker
    import tempfile
    import shutil

    client = docker.from_env()

    # Skip if no packages built
    deb_dir = project_root / 'build' / 'debs' / distro / 'arm64'
    if not deb_dir.exists() or not list(deb_dir.glob('liblgpio1_*.deb')):
        pytest.skip(f"liblgpio not built for {distro}")

    try:
        # Create container from debian base
        container = client.containers.run(
            f'debian:{distro}-slim',
            platform='linux/arm64',
            command='sleep infinity',
            detach=True,
            remove=True
        )

        try:
            # Copy DEB to container
            runtime_deb = list(deb_dir.glob('liblgpio1_*.deb'))[0]
            dev_deb = list(deb_dir.glob('liblgpio-dev_*.deb'))[0]

            # Create tar with DEBs
            with tempfile.TemporaryDirectory() as tmpdir:
                tmpdir_path = Path(tmpdir)
                shutil.copy(runtime_deb, tmpdir_path)
                shutil.copy(dev_deb, tmpdir_path)

                import tarfile
                tar_path = tmpdir_path / 'packages.tar'
                with tarfile.open(tar_path, 'w') as tar:
                    tar.add(runtime_deb, arcname=runtime_deb.name)
                    tar.add(dev_deb, arcname=dev_deb.name)

                with open(tar_path, 'rb') as tar_file:
                    container.put_archive('/tmp/', tar_file)

            # Install runtime package
            exit_code, output = container.exec_run(
                f'dpkg -i /tmp/{runtime_deb.name}',
                workdir='/tmp'
            )

            assert exit_code == 0, f"Runtime package install failed: {output.decode()}"

            # Install dev package
            exit_code, output = container.exec_run(
                f'dpkg -i /tmp/{dev_deb.name}',
                workdir='/tmp'
            )

            assert exit_code == 0, f"Dev package install failed: {output.decode()}"

            # Verify library is installed and accessible
            exit_code, output = container.exec_run('ldconfig -p | grep lgpio')
            assert exit_code == 0, "lgpio library not found by ldconfig"

            # Verify headers are installed
            exit_code, output = container.exec_run('ls /usr/include/lgpio.h')
            assert exit_code == 0, "lgpio.h header not found"

        finally:
            container.stop()

    except docker.errors.DockerException as e:
        pytest.skip(f"Docker not available: {e}")
```

**Step 4: Run installation test (integration)**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/test_apt_repository.py::test_install_liblgpio_in_container -v -m integration`
Expected: SKIP if no packages, PASS if packages exist and Docker available

**Step 5: Commit APT repository tests**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/test_apt_repository.py
git commit -m "feat: add APT repository validation tests

- Verify repository directory structure
- Validate conf/distributions configuration
- Check Release and Packages files for each distro
- Test package installation in clean container
- Mark integration tests with @pytest.mark.integration

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: Test Runner Script and Documentation

**Files:**
- Create: `tests/run_tests.sh`
- Create: `tests/README.md`
- Modify: `README.md`

**Step 1: Write test runner script**

```bash
# tests/run_tests.sh
#!/usr/bin/env bash
# Test runner for PiTrac package validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run PiTrac package validation tests.

OPTIONS:
    -q, --quick         Run quick tests only (skip slow/integration)
    -f, --full          Run all tests including slow and integration
    -m, --metadata      Run metadata tests only
    -c, --contents      Run content tests only
    -b, --build         Run build process tests only
    -a, --apt           Run APT repository tests only
    -p, --parallel N    Run with N parallel workers (default: auto)
    -v, --verbose       Verbose output
    -h, --help          Show this help

EXAMPLES:
    $0 --quick                     # Fast tests only
    $0 --full --parallel 4         # All tests with 4 workers
    $0 --metadata --verbose        # Metadata tests with details

EOF
}

# Default options
RUN_QUICK=false
RUN_FULL=false
TEST_CATEGORY=""
PARALLEL=""
VERBOSE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quick)
            RUN_QUICK=true
            shift
            ;;
        -f|--full)
            RUN_FULL=true
            shift
            ;;
        -m|--metadata)
            TEST_CATEGORY="test_package_metadata.py"
            shift
            ;;
        -c|--contents)
            TEST_CATEGORY="test_package_contents.py"
            shift
            ;;
        -b|--build)
            TEST_CATEGORY="test_build_process.py"
            shift
            ;;
        -a|--apt)
            TEST_CATEGORY="test_apt_repository.py"
            shift
            ;;
        -p|--parallel)
            PARALLEL="-n $2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Check dependencies
log_info "Checking test dependencies..."
if ! python3 -m pytest --version >/dev/null 2>&1; then
    log_error "pytest not found. Install with: pip3 install -r tests/requirements.txt"
    exit 1
fi

# Build pytest command
PYTEST_CMD="python3 -m pytest tests/"

if [ -n "$TEST_CATEGORY" ]; then
    PYTEST_CMD="$PYTEST_CMD$TEST_CATEGORY"
fi

if [ "$RUN_QUICK" = true ]; then
    log_info "Running quick tests (excluding slow and integration)..."
    PYTEST_CMD="$PYTEST_CMD -m 'not slow and not integration'"
elif [ "$RUN_FULL" = true ]; then
    log_info "Running all tests including slow and integration..."
else
    log_info "Running standard test suite (use --quick or --full for different coverage)..."
    PYTEST_CMD="$PYTEST_CMD -m 'not slow'"
fi

if [ -n "$PARALLEL" ]; then
    PYTEST_CMD="$PYTEST_CMD $PARALLEL"
fi

if [ -n "$VERBOSE" ]; then
    PYTEST_CMD="$PYTEST_CMD $VERBOSE"
else
    PYTEST_CMD="$PYTEST_CMD -v"
fi

# Run tests
log_info "Executing: $PYTEST_CMD"
if $PYTEST_CMD; then
    log_success "All tests passed!"
    exit 0
else
    log_error "Some tests failed"
    exit 1
fi
```

**Step 2: Make script executable**

Run: `chmod +x /home/cgallopo/dev/pitrac/packages/tests/run_tests.sh`
Expected: Script is now executable

**Step 3: Create test documentation**

```markdown
# tests/README.md
# PiTrac Package Validation Tests

Comprehensive test suite for validating DEB package creation, metadata, content, and installation across Debian distributions (Bookworm and Trixie).

## Overview

This test framework validates:
- **Package Metadata**: Control fields, versions, architectures, dependencies
- **Package Contents**: File locations, library splits (runtime/dev), permissions
- **Build Process**: Dockerfile validity, build scripts, Makefile targets
- **APT Repository**: Structure, configuration, package installation

## Quick Start

```bash
# Install test dependencies
pip3 install -r tests/requirements.txt

# Run quick tests (5-10 minutes)
./tests/run_tests.sh --quick

# Run all tests including slow builds (1-2 hours)
./tests/run_tests.sh --full

# Run specific test category
./tests/run_tests.sh --metadata
./tests/run_tests.sh --contents
./tests/run_tests.sh --build
./tests/run_tests.sh --apt
```

## Test Organization

```
tests/
├── conftest.py                   # Pytest configuration and fixtures
├── requirements.txt              # Python dependencies
├── run_tests.sh                  # Test runner script
├── utils/                        # Shared utilities
│   ├── package_inspector.py     # DEB metadata extraction
│   ├── docker_builder.py        # Docker build helpers
│   └── apt_validator.py         # APT repository validation
├── test_structure.py             # Project structure tests
├── test_package_metadata.py      # Control file validation
├── test_package_contents.py      # File location and content tests
├── test_build_process.py         # Dockerfile and build script tests
└── test_apt_repository.py        # Repository structure and install tests
```

## Test Categories

### Package Metadata Tests (`test_package_metadata.py`)

Validates control file fields for all packages:
- Required fields present (Package, Version, Architecture, Maintainer, Description)
- Version matches expected per distribution
- Architecture is arm64
- Dependencies are correctly declared
- Dev packages depend on runtime packages

**Run:** `pytest tests/test_package_metadata.py -v`

### Package Contents Tests (`test_package_contents.py`)

Validates file locations and organization:
- Runtime packages contain only `.so.*` files
- Dev packages contain headers (`.h`, `.hpp`)
- Dev packages contain `.so` symlinks (without version)
- Libraries in correct multiarch directory (`/usr/lib/aarch64-linux-gnu/`)
- Pkg-config files present in dev packages
- Executables in correct locations

**Run:** `pytest tests/test_package_contents.py -v`

### Build Process Tests (`test_build_process.py`)

Validates build infrastructure:
- All Dockerfiles exist and are valid
- Required ARGs declared (PACKAGE_VERSION, DEBIAN_ARCH, DEBIAN_DISTRO)
- Build scripts recognize all packages
- Makefile has targets for both distributions
- Integration test: Full lgpio build (marked `@pytest.mark.slow`)

**Run:** `pytest tests/test_build_process.py -v -m "not slow"`

### APT Repository Tests (`test_apt_repository.py`)

Validates repository structure:
- Required directories exist (conf/, dists/, pool/)
- `conf/distributions` is valid
- Release files present for each distribution
- Packages files generated correctly
- Integration test: Package installation in container (marked `@pytest.mark.integration`)

**Run:** `pytest tests/test_apt_repository.py -v -m "not integration"`

## Fixtures and Parametrization

Tests are parametrized across distributions and architectures:

```python
@pytest.fixture(params=['bookworm', 'trixie'])
def distro(request):
    return request.param

@pytest.fixture(params=['arm64'])
def arch(request):
    return request.param
```

This runs each test for both Bookworm and Trixie automatically.

## Test Markers

- `@pytest.mark.slow`: Tests that take >5 minutes (full builds)
- `@pytest.mark.integration`: Tests requiring Docker containers
- `@pytest.mark.parametrize`: Tests run across multiple inputs

## Prerequisites

Tests require packages to be built first:

```bash
# Build packages for testing
make build-all-bookworm
make build-all-trixie
```

Tests will **skip** if packages don't exist (not fail).

## Utilities

### PackageInspector

Extracts metadata and contents from DEB files:

```python
from tests.utils import PackageInspector

inspector = PackageInspector('/path/to/package.deb')
fields = inspector.get_control_fields()
contents = inspector.get_package_contents()
deps = inspector.get_dependencies()
```

### DockerBuilder

Validates Dockerfiles and performs builds:

```python
from tests.utils import DockerBuilder

builder = DockerBuilder(project_root)
args = builder.get_required_build_args('docker/Dockerfile.lgpio')
success, output = builder.build_image(
    'docker/Dockerfile.lgpio',
    'test-image:latest',
    build_args={'PACKAGE_VERSION': '0.2.2-1', 'DEBIAN_DISTRO': 'bookworm'}
)
```

### AptValidator

Validates APT repository structure:

```python
from tests.utils import AptValidator

validator = AptValidator(project_root)
distros = validator.get_configured_distributions()
packages = validator.get_package_list('bookworm', 'main')
```

## CI Integration

Recommended CI workflow:

```yaml
- name: Run quick tests
  run: ./tests/run_tests.sh --quick --parallel 4

- name: Build all packages
  run: make build-all

- name: Run full validation
  run: ./tests/run_tests.sh --full
```

## Troubleshooting

**Tests skip with "No packages built":**
- Run `make build-all-bookworm` or `make build-all-trixie` first

**Docker errors:**
- Ensure Docker daemon is running
- Ensure user is in `docker` group
- Run `docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`

**Import errors:**
- Install dependencies: `pip3 install -r tests/requirements.txt`

**Permission errors:**
- Make test script executable: `chmod +x tests/run_tests.sh`

## Adding New Tests

1. Choose appropriate test file based on what you're testing
2. Use existing fixtures (`project_root`, `distro`, `arch`)
3. Use parametrization for multi-distribution tests
4. Skip tests if prerequisites missing (don't fail):
   ```python
   if not packages_exist:
       pytest.skip("Packages not built")
   ```
5. Mark slow/integration tests appropriately
6. Update this README with new test descriptions

## Test Coverage Goals

- ✅ All packages have valid metadata
- ✅ Runtime/dev packages correctly split
- ✅ Dependencies declared correctly
- ✅ All Dockerfiles buildable
- ✅ Packages installable in clean environment
- ✅ Repository structure valid for both distributions
```

**Step 4: Update main README with testing section**

Run: `cd /home/cgallopo/dev/pitrac/packages && head -150 README.md > /tmp/readme_head.txt`
Expected: First part of README captured

**Step 5: Add testing section to main README**

Edit `README.md` to add after build instructions:

```markdown
## Testing

### Package Validation

Comprehensive test suite validates all built packages:

```bash
# Install test dependencies
pip3 install -r tests/requirements.txt

# Run all tests (except slow integration tests)
./tests/run_tests.sh

# Run quick tests only
./tests/run_tests.sh --quick

# Run specific category
./tests/run_tests.sh --metadata
./tests/run_tests.sh --contents
```

See [tests/README.md](tests/README.md) for detailed documentation.

### What's Tested

- **Package Metadata**: Control fields, versions, dependencies
- **Package Contents**: File locations, library splits, permissions
- **Build Process**: Dockerfile validity, build scripts
- **APT Repository**: Structure, installation in containers
```

**Step 6: Test the test runner**

Run: `cd /home/cgallopo/dev/pitrac/packages && ./tests/run_tests.sh --help`
Expected: Usage information displayed

**Step 7: Commit test documentation**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add tests/run_tests.sh tests/README.md README.md
git commit -m "feat: add test runner and documentation

- Create run_tests.sh with multiple run modes
- Add comprehensive tests/README.md
- Update main README with testing section
- Document all test categories and utilities
- Provide troubleshooting guide

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: Pytest Configuration and Final Integration

**Files:**
- Create: `pytest.ini`
- Modify: `tests/conftest.py`

**Step 1: Create pytest configuration file**

```ini
# pytest.ini
[pytest]
# Test discovery
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Test paths
testpaths = tests

# Markers
markers =
    slow: marks tests as slow (deselect with '-m "not slow"')
    integration: marks tests as integration tests requiring Docker
    unit: marks tests as fast unit tests

# Output options
addopts =
    --strict-markers
    --tb=short
    --disable-warnings
    -ra

# Coverage (optional, requires pytest-cov)
# addopts = --cov=. --cov-report=html --cov-report=term

# Timeout for all tests (requires pytest-timeout)
timeout = 300

# Parallel execution (requires pytest-xdist)
# Run with: pytest -n auto
```

**Step 2: Add conftest enhancements for better reporting**

```python
# tests/conftest.py (add to end of file)

# Custom test report header
def pytest_report_header(config):
    """Add custom header to test report"""
    return [
        "PiTrac Package Validation Test Suite",
        f"Project root: {PROJECT_ROOT}",
        f"Testing distributions: {', '.join(DISTRIBUTIONS)}",
        f"Testing architectures: {', '.join(ARCHITECTURES)}"
    ]

# Skip collection of test files if no packages built
def pytest_collection_modifyitems(config, items):
    """Add skip markers based on available packages"""
    deb_dir = PROJECT_ROOT / 'build' / 'debs'

    if not deb_dir.exists():
        skip_no_packages = pytest.mark.skip(reason="No packages built - run 'make build-all' first")
        for item in items:
            # Don't skip structure tests
            if 'test_structure' not in item.nodeid and 'test_dockerfile' not in item.nodeid:
                item.add_marker(skip_no_packages)
```

**Step 3: Run full test suite to verify setup**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/ -v --collect-only`
Expected: Shows all collected tests with markers

**Step 4: Create GitHub Actions workflow (optional)**

```yaml
# .github/workflows/test-packages.yml
name: Package Validation Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

jobs:
  quick-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r tests/requirements.txt

      - name: Run quick tests
        run: |
          ./tests/run_tests.sh --quick --parallel auto

  build-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        distro: [bookworm, trixie]
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y reprepro dpkg-dev
          pip install -r tests/requirements.txt

      - name: Build lgpio for ${{ matrix.distro }}
        run: make build-lgpio-${{ matrix.distro }}

      - name: Run validation tests
        run: |
          ./tests/run_tests.sh --metadata --contents --parallel auto

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ matrix.distro }}
          path: |
            build/debs/${{ matrix.distro }}/
```

**Step 5: Test pytest configuration**

Run: `cd /home/cgallopo/dev/pitrac/packages && python3 -m pytest tests/ -v -m "not slow and not integration"`
Expected: Runs fast tests only

**Step 6: Commit pytest configuration**

```bash
cd /home/cgallopo/dev/pitrac/packages
git add pytest.ini tests/conftest.py
git commit -m "feat: add pytest configuration and reporting enhancements

- Create pytest.ini with markers and test discovery
- Add custom test report headers
- Configure timeout and parallel execution
- Auto-skip tests when packages not built
- Add GitHub Actions workflow template (optional)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Verification and Usage

Once implementation is complete, verify the framework:

**Step 1: Run structure tests (no build required)**

```bash
cd /home/cgallopo/dev/pitrac/packages
python3 -m pytest tests/test_structure.py -v
python3 -m pytest tests/test_build_process.py -v -m "not slow"
```

Expected: All PASS

**Step 2: Build one package for testing**

```bash
make build-lgpio-bookworm
```

Expected: liblgpio1 and liblgpio-dev DEBs created

**Step 3: Run validation on built package**

```bash
./tests/run_tests.sh --metadata --contents
```

Expected: All tests PASS or SKIP

**Step 4: Build all packages and run full suite**

```bash
make build-all-bookworm
./tests/run_tests.sh --full
```

Expected: Comprehensive validation results

**Step 5: Integrate into Makefile**

Add to Makefile:

```makefile
.PHONY: test test-quick test-full

test: ## Run standard test suite
	./tests/run_tests.sh

test-quick: ## Run quick tests only
	./tests/run_tests.sh --quick

test-full: build-all ## Build all packages and run full test suite
	./tests/run_tests.sh --full
```

---

## Summary

This plan creates a comprehensive validation framework with:

1. **Utilities** for package inspection, Docker builds, APT validation
2. **Metadata tests** for control files, versions, dependencies
3. **Content tests** for file locations, library splits, permissions
4. **Build tests** for Dockerfiles, scripts, and integration
5. **Repository tests** for APT structure and installation
6. **Documentation** with usage examples and troubleshooting
7. **Test runner** with multiple execution modes
8. **CI integration** ready for GitHub Actions

Each task is bite-sized (2-5 minutes per step) with clear verification steps and commit boundaries.
