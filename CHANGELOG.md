# Changelog

## 1.0.4

- Fixed deposits to checked personal Guild Banks reducing earnings when the initial bank balance is unavailable.
- Match deposit/withdrawal requests to actual wallet changes and avoid processing their later bank updates twice.
- Keep ordinary spending and unchecked-bank activity in the ledger; failed requests do not create transfers.
- Added tests for all account/character period totals, missing initial balances, delayed bank updates, withdrawals, and failed requests.

## 1.0.3

- Fixed duplicate guild-bank entries for characters in the same guild on different realms.
- Identify banks by the guild ID rather than the character realm.
- Consolidate older entries as affected characters log in, preserving the personal-bank setting and latest known balance without adding duplicate balances.
- Keep different guilds with identical names separate and normalize verified aliases after importing IRS records.
- Publish only the install ZIP, without checksum attachments.

## 1.0.2

- Added Settings > Profiles with IRS Default and ElvUI Inspired appearance presets.
- Apply presets immediately, restore saved choices on reload, and retain font settings and earnings.
- Copy the appearance preset when importing full IRS records.
- Added regression checks for color restoration, saved presets, and imported appearance.

## 1.0.1

Initial GitHub release of IRS Lite.

- Retained the IRS title bar, four earnings totals, character subtotals, and seven-day earnings chart.
- Added the Lite manual, daily corrections, and account total corrections.
- Kept minimap, internal-transfer, and main-window font settings.
- Added Settings > Import > Import IRS files, with a preview and confirmation before replacing Lite history.
- Kept imports independent of the original IRS records and excluded removed feature data.
- Corrected corrupted symbols in the title, tooltips, chart placeholders, and transfer text.
- Added Lua 5.1 regression checks and reproducible release packaging.

## 1.0.0

- Created the standalone Lite edition with its own SavedVariables database.
