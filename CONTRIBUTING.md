# Contributing to IRS Lite

Bug reports, reproducible test cases, and feature suggestions are welcome through this repository's issue forms.

Include the IRS Lite version, WoW Retail version, exact reproduction steps, and relevant Lua errors. For import problems, also include the full IRS version and whether both addons were enabled. Remove account names and other personal information before posting screenshots or logs. Do not attach SavedVariables files publicly.

This project retains the original IRS proprietary license. Code contributions require the maintainer's agreement before opening a pull request; see [LICENSE](LICENSE).

## Local checks

Use Python 3.12 or later:

```sh
python -m pip install -r requirements-dev.txt
python scripts/validate.py
python scripts/package.py
```

Validation runs the Lua 5.1 simulation and checks the manifest and install assets. The package builder creates a ZIP containing `IRS Lite/IRS Lite.toc` and only the required runtime files, documentation, and artwork. Build outputs and local dependencies are ignored by Git.

Game checks remain necessary for actual window layout, bank event timing, and addon interactions. See [the release checklist](docs/RELEASE_CHECKLIST.md).
