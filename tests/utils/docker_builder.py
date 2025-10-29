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

        self._docker_client = None

    @property
    def docker_client(self):
        """Lazy initialization of Docker client"""
        if self._docker_client is None:
            self._docker_client = docker.from_env()
        return self._docker_client

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
