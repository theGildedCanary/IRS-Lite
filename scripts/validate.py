"""Run repository validation from any working directory."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
for test in ('tests/smoke_test.py', 'tests/test_package.py'):
    subprocess.run([sys.executable, str(ROOT / test)], cwd=ROOT, check=True)
print('All IRS Lite checks passed.')
