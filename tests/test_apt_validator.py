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
