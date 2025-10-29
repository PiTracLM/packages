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
