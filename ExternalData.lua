-- AHelper: external (other realm) price data.
-- This file is OVERWRITTEN by tools/fetch_prices.py. Re-run the script and /reload to refresh.
-- Format:
-- AHelper_External = {
--   generated = <unix time>,
--   realms = { ["Realm-Faction"] = { [itemID] = { mkt, min, qty }, ... }, ... },
-- }
AHelper_External = AHelper_External or { generated = 0, realms = {} }
