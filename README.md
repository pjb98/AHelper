# AHelper – Auction House helper for WoW Classic (Anniversary / "Forever" realms)

A personal gold-making addon for the Classic Era client.

## Install

1. Copy this folder into `World of Warcraft/_forever_/Interface/AddOns/` (or `_classic_era_` for Classic Era) and name the folder **`AHelper`** (it must match `AHelper.toc`).
2. If the addon shows as "out of date", tick **Load out of date AddOns** or update the `## Interface:` line in `AHelper.toc` to the current client build (type `/dump select(4, GetBuildInfo())` in game).
3. Open the auction house and click the **AHelper** button (top-right of the AH window) or type `/ahh`.

## Releases, CurseForge and addon managers

Pushing a version tag (or running the workflow from the Actions tab with a version) builds a ready-to-install zip (folder already named `AHelper`, `tools/` left out) using `.github/workflows/release.yml`:

```bash
git tag v0.2.0
```

```bash
git push origin v0.2.0
```

- **GitHub Release:** the zip is attached to a release on the repo's Releases page. Addon managers like WowUp can install and update from that.
- **CurseForge:** create the project on CurseForge first, add `## X-Curse-Project-ID: <id>` to `AHelper.toc`, and add a repository secret `CF_API_KEY` (from <https://legacy.curseforge.com/account/api-tokens>). Later tags then upload to CurseForge too.

## Features

| Feature | What it does |
|---|---|
| **Buy popup** | Pops up when any listing you see (full scan, sniper, or normal browsing) is **cheaper than its vendor sell price**, far below market value, or under a watchlist max price. Click **Buy** to buy it out. Shows profit, seller, and queues multiple hits by profit. |
| **Full scan** | Uses the server's GetAll scan (allowed once every 15 min) to record the whole AH: market value, lowest price, quantity, and an estimate of how many items sold. |
| **Sniper** | Repeatedly searches your watchlist + all farmable items and pops up deals the moment they're listed. |
| **Deals tab** | Everything currently under vendor price or far under market, with total cost and profit if you buy it all. |
| **Flips tab** | Buy everything under 80% of market, relist at ~97%. Shows ROI and *Days* = how many days of normal sales it takes to sell what you'd buy (risk). |
| **Farming tab** | Curated open-world farmables (cloth, herbs, ore, leather, elementals, fish, gems…) ranked by **Gold/day** = estimated units sold per day × market price, with farming spots and a 7d vs 30d trend. Tick *all items* to rank every item on the AH. Edit `FarmDB.lua` to add your own. |
| **Time of Day tab** | Learns each item's price at every hour of the day (relative to its own average, so trends don't fool it) and lists items with a **consistent** cheap hour and expensive hour. Includes a whole-market by-hour chart. |
| **Investments tab** | *cross-realm*: items much cheaper here than the median price on other realms. *region*: cheaper than TSM's region-wide average. *dip*: items well below their own 30-day average that are still selling. |
| **Watchlist** | Items the sniper always checks, each with an optional max price. Right-click any row in any tab to add/remove. |
| **Sell helper** | When you drop an item in the Auctions tab it fills in an undercut price (but refuses to dump far below market) and warns you when an item is worth more at a vendor. |
| **% of market on listings** | Like TSM: every row in the auction house (browse results, buy lists, competitor lists when selling) shows its price as a % of market value. Blue < 50%, green < 80%, yellow ≈ market, orange/red overpriced, **VENDOR** = cheaper than the vendor price. Move the label with the *% label position* setting if it overlaps a column. |
| **TradeSkillMaster data** | If TSM is installed, AHelper uses TSM's market value until it has 3+ days of its own scans (deal popups work from day one), TSM's region sold-per-day for the Farming tab and tooltips, and TSM's region average for Investments. Turn off with *Use TradeSkillMaster price & sales data*. |
| **Buy keybind & Queue all** | Bind **Buy** / **Skip** under *Key Bindings → AddOns → AHelper* (a key or the mouse wheel). The *Queue all* button on the Deals tab loads every deal into the popup, then each key press buys the next one. Stackables buy every qualifying unit in one press. |
| **Minimap button** | Left-click opens the window, right-click runs a full scan (at the AH), shift-right-click toggles the sniper. Drag it around the minimap; hide it with `/ahh minimap` or on the Settings tab. |
| **Tooltips** | Market value, lowest price, est. sales/day, other-realm median and best buy/sell hours on every item tooltip. |

Row clicks: **click** = search it in the AH, **shift-click** = link in chat, **right-click** = watchlist, **ctrl-click** = ignore.

## Getting good data

The history-based features improve the more you scan:

- Do a **Full scan** every time you visit the AH (it unlocks every 15 minutes).
- **Time of Day** needs scans at many different hours across several days (default: ≥3 samples in at least 3 different hours).
- **Sold/day** estimates need at least two scans on the same day, within 2 hours of each other. An auction that was *Long/Very Long* and then vanished counts as sold, so cancellations also get counted. Treat it as a relative measure, not an exact one.
- Scanning on alts on **other realms or factions** automatically gives you cross-realm data (everything is account-wide in `AHelperDB`).

## Cross-realm prices (optional)

Addons can't access the internet, so `tools/fetch_prices.py` downloads other realms' AH data from Blizzard's API and writes `ExternalData.lua`.

1. Create a free API client at <https://develop.battle.net/access/clients>.
2. Set `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET` (or create `tools/config.json` with `client_id`, `client_secret`, `region`, `realms`). The file is git-ignored.
3. Find realm slugs, then fetch:

```bash
python tools/fetch_prices.py --list-realms
```

```bash
python tools/fetch_prices.py --realms realm-one,realm-two --factions alliance,horde
```

4. `/reload` in game.

The default namespace is `dynamic-classic1x-<region>` (Classic Era). If your realms don't appear, try `--namespace dynamic-classic-us` or check Blizzard's API docs. Blizzard may not expose every realm type.

## Commands

```
/ahh                 toggle window
/ahh scan            full scan
/ahh snipe           start/stop sniper
/ahh watch <item>    add to watchlist (link, name or id)
/ahh unwatch <item>
/ahh ignore <item>   toggle ignore for popups
/ahh minimap         show/hide the minimap button
/ahh settings        list settings
/ahh set <key> <v>   change a setting (prices are in copper: 1g = 10000)
/ahh reset realm     wipe this realm's history
```

Most settings can also be changed on the **Settings** tab.

## Notes / limits

- Works with both auction house systems: the old Classic one and the modern one that WoW Forever uses (`C_AuctionHouse`). On the modern one:
  - Stackable goods (cloth, herbs, ore...) are bought as "commodities". The popup asks the server for a live price first, so the Buy button says *Checking...* for a moment. It then buys the cheapest units, and shows *(price changed)* if the total moved.
  - Gear is bought as a specific auction found by a live search.

- Blizzard requires a real click or key press for every purchase, so the addon can't buy on its own. Tools that press keys or click for you break the Terms of Service. One key press per purchase (the Buy keybind) is how TSM works too, and is allowed.
- The popup never offers a single purchase above `maxPopupSpend` (default 100g) and skips your own auctions.
- Hours use your computer's clock.
