"""Build a reproducible WoW install archive from an explicit runtime allowlist."""
from pathlib import Path
import argparse
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'IRS Lite.toc'
ASSETS = (
    'Media/IRSButton.tga', 'Media/IRSTitleIcon.tga',
    'Media/fonts/2002.ttf', 'Media/fonts/2002b.ttf', 'Media/fonts/README.md',
)
DOCUMENTS = ('README.md', 'CHANGELOG.md', 'LICENSE')


def manifest():
    text = (ROOT / MANIFEST).read_text(encoding='utf-8-sig')
    version = re.search(r'^## Version:\s*(\d+\.\d+\.\d+)\s*$', text, re.M)
    if not version:
        raise ValueError('The manifest needs a three-part Version.')
    modules = tuple(line.strip().replace('\\', '/') for line in text.splitlines()
                    if line.strip() and not line.lstrip().startswith('#'))
    if not modules or len(set(modules)) != len(modules):
        raise ValueError('The manifest has no modules or contains duplicate paths.')
    return version.group(1), modules


def release_files():
    version, modules = manifest()
    paths = (MANIFEST, *modules, *ASSETS, *DOCUMENTS)
    for name in paths:
        relative = Path(name)
        path = ROOT / relative
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'Unsafe package path: {name}')
        if not path.is_file() or not path.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError(f'Missing or external package file: {name}')
        if any(part.is_symlink() for part in (path, *path.parents) if part != ROOT.parent):
            raise ValueError(f'Package files cannot use symlinks: {name}')
    return version, paths


def build(output, requested_version=None):
    version, files = release_files()
    if requested_version and requested_version.removeprefix('v') != version:
        raise ValueError(f'Release tag {requested_version} does not match manifest version {version}.')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'IRS-Lite-{version}.zip'
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(f'IRS Lite/{name}', date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (ROOT / name).read_bytes(), compresslevel=9)
    with zipfile.ZipFile(target) as archive:
        expected = {f'IRS Lite/{name}' for name in files}
        if set(archive.namelist()) != expected or archive.testzip() is not None:
            raise ValueError('The generated archive failed verification.')
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', help='Expected release version or tag (for example v1.0.1).')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    arguments = parser.parse_args()
    try:
        print(build(arguments.output, arguments.version))
    except ValueError as error:
        parser.error(str(error))
