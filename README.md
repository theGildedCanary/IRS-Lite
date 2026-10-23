# IRS Lite — Income Records System

[![Validate](https://github.com/theGildedCanary/IRS-Lite/actions/workflows/validate.yml/badge.svg)](https://github.com/theGildedCanary/IRS-Lite/actions/workflows/validate.yml)

A standalone Retail edition with the original title bar and artwork, reduced to:

- **Dashboard:** Today, This Reset, This Month, Total Recorded, current-character subtotals, and the seven-day daily earnings bar graph.
- **Tools:** Lite user manual, Daily Income Adjustment, and Overall Income Adjustment.
- **Settings:** Minimap Button, Transfers, main-window fonts, IRS Default / ElvUI Inspired appearance presets, and Import IRS files.

Gold amounts are stored in copper. Earnings are observed wallet gains minus spending. Warband Bank transfers and transfers involving explicitly marked personal Guild Banks are filtered from earnings. Mailed and traded gold between characters cannot be identified automatically. Checked guild-bank deposits and withdrawals are matched to their wallet changes even if the initial bank balance has not loaded. The corresponding bank update is consumed once, so it cannot exclude another transaction. Other bank event timing may delay a ledger entry briefly. Use Tools to correct missed or misclassified changes.

## Install and open

Download the install ZIP from [Releases](https://github.com/theGildedCanary/IRS-Lite/releases), then extract the **IRS Lite** folder into your Retail `Interface/AddOns` directory. Use the `IRS-Lite-VERSION.zip` release asset; GitHub's automatic source downloads use a different folder name.

The folder and manifest must be `Interface/AddOns/IRS Lite/IRS Lite.toc`. Fully restart WoW for the new addon to appear, then enable **IRS Lite — Income Records System** in the addon list.

Use `/irslite` or `/irsl` to toggle the window. Add `dashboard`, `tools`, or `settings` to open a page directly. `/irslite help` opens the manual. Left-click the minimap button to toggle Lite; right-click to open Settings. Drag the window to move it; Escape closes it.

Lite uses **IRSLiteDB**, its own account-wide SavedVariables database. To copy existing IRS history:

1. Enable both **Income Records System** and **IRS Lite** in the AddOns list, then reload.
2. Open `/irslite settings` and select **Import**.
3. Click **Import IRS files**, review the available character/day counts and total, then confirm **Replace Lite history**.
4. Disable the full addon afterward if you only want to run Lite.

Import replaces Lite's history with a separate copy of IRS's account and character totals, daily/reset/monthly earnings, overall correction, known guild banks, transfer settings, minimap preference, main fonts, and appearance preset. It does not add the totals together, and it never changes IRS's original records. Imports are manual; the editions save independently afterward. Projects, reserves, reports, and mini dashboard data are excluded. Main font sizes are limited to the sizes Lite supports.

WoW addons cannot browse SavedVariables files directly. The **Import IRS files** option reads the full addon's loaded records; **IncomeRecordsSystem** is an optional load-order dependency, so Lite still runs when the full addon is disabled or uninstalled. Until the full addon is enabled and its records are available, the import screen explains how to enable it. The full addon retains `/irs`.

## Guild banks across realms

Lite identifies each guild by its unique guild ID, so characters on different realms share one bank entry and one personal-bank setting. When upgrading from older versions, log into a guild character on each affected realm once to consolidate its old entry. The latest known balance is kept; duplicate balances are never added together. Different guilds with the same name remain separate.

## Appearance presets

Open **Settings > Profiles** to choose **IRS Default** (warm brown and gold) or **ElvUI Inspired** (dark gray panels and neutral text). Presets apply immediately and persist across reloads and characters. ElvUI is not required. Switching presets preserves your font choices and all earnings history. Import IRS files also copies the selected appearance preset.

## Organization

| File | Responsibility |
| --- | --- |
| `Core/Core.lua` | Database, account/character net ledgers, period keys, guild-bank reads, money formatting |
| `UI/LayoutStyle.lua` | Saved appearance presets and live color updates |
| `Core/Fonts.lua` | Font faces, semantic sizes, live updates |
| `Core/Import.lua` | Manual IRS history preview, conversion, and independent copy |
| `Core/Events.lua` | Login, money/bank events, slash commands |
| `Features/Transfers.lua` | Transfer matching and personal guild-bank settings |
| `Features/Tools.lua` | Manual and earnings corrections |
| `UI/UI.lua` | Title bar, navigation, dashboard, graph, minimap button |
| `UI/Settings.lua` | Minimap, Transfers, Fonts, Profiles, and Import settings |

Only these nine Lua modules load. Lite contains no projects, reserves, token market, mini dashboard, reports, auction-mail classification, statistics scanning, contributor page, or startup timing instrumentation. Transfer matching retains short-lived runtime queues for different bank/wallet event orders and late corrections. Deferred entries keep their original day/reset/month keys.

## Validation

Install the test dependencies with `python -m pip install -r requirements-dev.txt`, then run `python scripts/validate.py`. The regression harness uses `lupa` with Lua 5.1. It simulates WoW's APIs and checks module loading, namespace isolation, account and character earnings, corrections, bank event orders, partial matches, late transfer reversals, date rollover, pending-entry logout, page navigation, fonts, and appearance presets. Import checks cover schema conversion, source isolation, confirmation/cancel, repeat imports, invalid history, and pending bank events. The harness does not modify WoW or saved records.

Live checks still needed: open each page, inspect fonts and the graph, toggle the minimap setting, then deposit and withdraw gold from the Warband Bank and a marked personal Guild Bank. Confirm earnings stay unchanged for internal transfers, then make a purchase and confirm earnings decrease.


## Development and releases

The [GitHub repository](https://github.com/theGildedCanary/IRS-Lite) includes issue forms, Windows/Linux validation, and an install-package builder. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [release checklist](docs/RELEASE_CHECKLIST.md).

`python scripts/package.py` creates `dist/IRS-Lite-1.0.4.zip`. The ZIP uses an explicit file list and the required `IRS Lite` install folder; tests, build dependencies, Git metadata, and saved records are excluded. Publishing a GitHub Release with a tag matching the TOC version runs validation and attaches the install package automatically.

## License and credits

Copyright 2026 Gilded Canary. IRS Lite retains the original IRS proprietary license; source visibility does not grant redistribution rights. See [LICENSE](LICENSE). Bundled WoW font provenance is documented in [Media/fonts/README.md](Media/fonts/README.md). World of Warcraft and related assets belong to Blizzard Entertainment; this addon is not affiliated with or endorsed by Blizzard.
