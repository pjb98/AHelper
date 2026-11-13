-- AHelper: read prices from TradeSkillMaster (if installed) through its public TSM_API.
-- TSM's desktop app keeps these up to date from Blizzard's hourly auction data, so AHelper gets
-- market values and sales stats without needing its own scan history.
local _, ns = ...
local T = {}
ns.TSM = T

local cache = {}
local CACHE_SECONDS = 60

local function api()
    if not (ns.settings and ns.settings.useTSM) then return nil end
    return TSM_API and TSM_API.GetCustomPriceValue
end

function T.Available()
    return api() ~= nil
end

-- Evaluate a TSM custom price string (e.g. "dbmarket") for an item. Returns a number or nil.
function T.Value(source, itemID)
    local f = api()
    if not f or not itemID then return nil end
    local key = source .. ":" .. itemID
    local c = cache[key]
    local now = GetTime()
    if c and now - c.t < CACHE_SECONDS then return c.v end
    local ok, v = pcall(f, source, "i:" .. itemID)
    if not ok or type(v) ~= "number" then v = nil end
    cache[key] = { v = v, t = now }
    return v
end

local function positive(v) return (v and v > 0) and v or nil end

-- Realm market value (TSM "DBMarket")
function T.Market(itemID) return positive(T.Value("dbmarket", itemID)) end

-- Region-wide average market value across all realms (TSM "DBRegionMarketAvg")
function T.RegionAvg(itemID) return positive(T.Value("dbregionmarketavg", itemID)) end

-- Region average sale price (what items actually sell for)
function T.RegionSaleAvg(itemID) return positive(T.Value("dbregionsaleavg", itemID)) end

-- Average units sold per day per realm across the region. Custom prices are rounded to whole numbers,
-- so scale up by 1000 inside TSM and back down here to keep the decimals.
function T.SoldPerDay(itemID)
    local v = T.Value("dbregionsoldperday*1000", itemID)
    return v and v / 1000 or nil
end

-- Chance a listing sells (0..1)
function T.SaleRate(itemID)
    local v = T.Value("dbregionsalerate*1000", itemID)
    if not v then return nil end
    local r = v / 1000
    if r > 1 then r = r / 1000 end -- in case TSM already reports it scaled
    return r
end

ns.On("AUCTION_HOUSE_SHOW", function() wipe(cache) end)
