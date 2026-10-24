# Release checklist

1. Update `IRS Lite.toc` and `CHANGELOG.md` to the same version.
2. Run `python -m pip install -r requirements-dev.txt`, then `python scripts/validate.py`.
3. In WoW Retail, open Dashboard, Tools, and all Settings sections. Check the title and text at supported font sizes and on a smaller display. Switch Profiles between IRS Default, ElvUI Inspired, and WoW Forever, check panels/text on every page, and verify the choice survives reload. In Forever, inspect the centered banner, header icons, rounded table corners, dark backgrounds at 75% opacity, button fills at 80% opacity, and light gold graph bars. Confirm original controls and backgrounds restore when switching away.
4. Confirm the chart handles positive, negative, and zero earnings, and the minimap toggle persists after reload.
5. Test Warband deposits/withdrawals and a marked personal Guild Bank, including an initially empty bank, a deposit made immediately after opening, and a deposit after `/reload` with the bank window still visible. Transfers should not change earnings; an ordinary purchase should reduce them. Log into guild characters on two realms and verify there is one shared bank row and personal-bank setting.
6. With both editions enabled, preview an import, cancel it, then confirm it. Check account/character totals and graph history; the original IRS records must remain unchanged.
7. Disable the full addon and confirm Lite still loads and retains the imported records.
8. Run `python scripts/package.py --version VERSION` and inspect the ZIP. Its top-level folder must be `IRS Lite`, with no saved data, credentials, test dependencies, or build tools.
9. Push the reviewed source to GitHub and wait for the Validate workflow to pass.
10. Create a GitHub Release with a tag such as `v1.0.6` matching the TOC version. Use the corresponding changelog entry as its description. Publishing the release runs validation again and attaches only the install ZIP.

GitHub's automatic source archives are development downloads. Users should install the `IRS-Lite-VERSION.zip` release asset to get the correct WoW folder name.
