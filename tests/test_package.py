"""Verify installation layout, packaging reproducibility, and exclusions."""
from pathlib import Path
import hashlib
import importlib.util
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package', ROOT / 'scripts/package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
version, files = package.release_files()
test_output = ROOT / 'build'
test_output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='irs-lite-package-', dir=test_output) as temporary:
    folder = Path(temporary)
    first, checksum = package.build(folder / 'first', f'v{version}')
    second, _ = package.build(folder / 'second', version)
    assert first.read_bytes() == second.read_bytes(), 'Builds are not reproducible.'
    assert checksum.read_text().split()[0] == hashlib.sha256(first.read_bytes()).hexdigest()
    with zipfile.ZipFile(first) as archive:
        assert 'IRS Lite/IRS Lite.toc' in archive.namelist()
        assert len(archive.namelist()) == len(files)
        for name in archive.namelist():
            assert name.startswith('IRS Lite/')
            assert not any(part in name for part in ['.git/', '.test-runtime/', 'SavedVariables/', 'tests/', 'scripts/', '.env'])
    try:
        package.build(folder / 'invalid', 'v999.0.0')
    except ValueError:
        pass
    else:
        raise AssertionError('Mismatched release versions must be rejected.')
print('PASS: release layout, checksum, reproducibility, exclusions, and tag-version match')
