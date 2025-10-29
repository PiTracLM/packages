"""
Utilities for validating APT repository structure and configuration.
"""
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

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
