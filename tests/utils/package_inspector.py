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
