-- AHelper: Core (namespace, saved variables, events, slash commands, utilities)
local ADDON, ns = ...
AHelper = ns -- global handle for /dump and macros

do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON, "Version")
    ns.version = (v and not v:find("^@")) and v or "dev"
end

local DEFAULTS = {
    settings = {
        vendorPopup        = true,  -- popup when an auction is cheaper than vendor sell price
        vendorMinProfit    = 50,    -- copper; ignore vendor flips worth less than this
        dealPopup          = true,  -- popup when an auction is far below market value
        dealMaxPct         = 50,    -- buyout per unit <= this % of market value
        dealMinProfit      = 5000,  -- copper (50s) minimum expected resale profit after AH cut
        dealMinSamples     = 3,     -- need at least this many days of data before trusting market value
        maxPopupSpend      = 1000000, -- copper (100g); never offer a single buy above this
        popupSound         = true,
        ahCut              = 0.05,  -- 5% AH cut on sales
        historyDays        = 45,    -- days of daily history to keep per item
        undercut           = 1,     -- copper to undercut by when suggesting a post price
        tooltip            = true,
        snipeInterval      = 3,     -- seconds between sniper queries (minimum, also throttled by server)
        investMinPct       = 25,    -- local price must be at least this % below reference to be an investment
        hourMinSamples     = 3,     -- samples per hour bucket needed for time-of-day analysis
        hourMinSpreadPct   = 15,    -- min % spread between cheapest and priciest hour
        useAuctionator     = true,  -- fall back to Auctionator prices when we have no data
        minimap            = true,  -- show the minimap button
        minimapAngle       = 220,   -- minimap button position in degrees
    },
    realms   = {},  -- [realmKey] = { items = { [itemID] = itemRecord }, lastScan = ts, scans = n }
    watch    = {},  -- [itemID] = { maxPrice = copper|nil }  sniper watchlist
    ignore   = {},  -- [itemID] = true  never pop up for these
    purchases = {}, -- log of buys made through AHelper
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns.Print(...)
    print("|cff33ff99AHelper|r:", ...)
end

function ns.Money(copper, short)
    if not copper then return "-" end
    local neg = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out
    if short and g >= 100 then
        out = string.format("|cffffd700%dg|r", g)
    elseif g > 0 then
        out = string.format("|cffffd700%dg|r |cffc7c7cf%02ds|r |cffeda55f%02dc|r", g, s, c)
    elseif s > 0 then
        out = string.format("|cffc7c7cf%ds|r |cffeda55f%02dc|r", s, c)
    else
        out = string.format("|cffeda55f%dc|r", c)
    end
    return neg and ("-" .. out) or out
end

function ns.Pct(x)
    if not x then return "-" end
    return string.format("%d%%", math.floor(x + 0.5))
end

function ns.ItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id)
end

-- Day number (days since epoch, local time) and local hour of day
function ns.DayNumber(ts)
    ts = ts or time()
    local d = date("*t", ts)
    return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

function ns.Hour(ts)
    return tonumber(date("%H", ts or time()))
end

function ns.RealmKey()
    local realm = GetRealmName() or "?"
    local faction = UnitFactionGroup("player") or "?"
    return realm .. "-" .. faction
end

function ns.RealmDB(key)
    key = key or ns.RealmKey()
    local r = AHelperDB.realms[key]
    if not r then
        r = { items = {}, scans = 0, lastScan = 0 }
        AHelperDB.realms[key] = r
    end
    return r
end

-- Cached GetItemInfo: returns name, link, quality, vendorSellPrice, stackSize
local itemCache = {}
function ns.ItemInfo(itemID)
    local c = itemCache[itemID]
    if c then return c.name, c.link, c.quality, c.vendor, c.stack end
    local name, link, quality, _, _, _, _, stack, _, _, vendor = GetItemInfo(itemID)
    if name then
        itemCache[itemID] = { name = name, link = link, quality = quality, vendor = vendor or 0, stack = stack or 1 }
        return name, link, quality, vendor or 0, stack or 1
    end
    -- not cached by client yet; also try what we stored from scans
    local rec = AHelperDB and ns.RealmDB().items[itemID]
    if rec then return rec.name, nil, rec.q, rec.v, nil end
    return nil
end

---------------------------------------------------------------------------
-- Event dispatch
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event) -- ignore events this client does not have
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for i = 1, #list do list[i](event, ...) end
    end
end)

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    AHelperDB = AHelperDB or {}
    copyDefaults(DEFAULTS, AHelperDB)
    ns.db = AHelperDB
    ns.settings = AHelperDB.settings
    if ns.OnInit then
        for _, fn in ipairs(ns.OnInit) do fn() end
    end
end)

ns.On("PLAYER_LOGIN", function()
    if ns.Data and ns.Data.Prune then ns.Data.Prune() end
end)

-- modules register init callbacks here
ns.OnInit = {}
function ns.RegisterInit(fn) table.insert(ns.OnInit, fn) end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function help()
    ns.Print("commands:")
    print("  /ahh                - toggle the AHelper window")
    print("  /ahh scan           - full (GetAll) scan of the auction house (every 15 min)")
    print("  /ahh snipe          - start/stop the sniper (cycles watchlist + farm items)")
    print("  /ahh watch <item>   - add item (link or name) to sniper watchlist")
    print("  /ahh unwatch <item> - remove item from watchlist")
    print("  /ahh ignore <item>  - never show buy popups for an item")
    print("  /ahh set <key> <v>  - change a setting (see /ahh settings)")
    print("  /ahh minimap        - show/hide the minimap button")
    print("  /ahh settings       - list settings")
    print("  /ahh reset realm    - wipe price history for this realm/faction")
end

local function resolveItem(arg)
    if not arg or arg == "" then return nil end
    local id = ns.ItemIDFromLink(arg) or tonumber(arg)
    if id then return id end
    local _, link = GetItemInfo(arg)
    if link then return ns.ItemIDFromLink(link) end
    -- search our own data by name
    for itemID, rec in pairs(ns.RealmDB().items) do
        if rec.name and rec.name:lower() == arg:lower() then return itemID end
    end
end

SLASH_AHELPER1 = "/ahh"
SLASH_AHELPER2 = "/ahelper"
SlashCmdList.AHELPER = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "scan" then
        ns.Scanner.StartFullScan()
    elseif cmd == "snipe" then
        ns.Scanner.ToggleSniper()
    elseif cmd == "watch" or cmd == "unwatch" or cmd == "ignore" then
        local id = resolveItem(rest)
        if not id then ns.Print("unknown item:", rest) return end
        if cmd == "watch" then
            AHelperDB.watch[id] = AHelperDB.watch[id] or {}
            ns.Print("watching", (ns.ItemInfo(id)) or id)
        elseif cmd == "unwatch" then
            AHelperDB.watch[id] = nil
            ns.Print("removed", (ns.ItemInfo(id)) or id)
        else
            AHelperDB.ignore[id] = not AHelperDB.ignore[id] or nil
            ns.Print(AHelperDB.ignore[id] and "ignoring" or "no longer ignoring", (ns.ItemInfo(id)) or id)
        end
    elseif cmd == "minimap" then
        ns.settings.minimap = not ns.settings.minimap
        ns.Minimap.Update()
        ns.Print("minimap button", ns.settings.minimap and "shown" or "hidden")
    elseif cmd == "settings" then
        local keys = {}
        for k in pairs(ns.settings) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do print("  " .. k .. " = " .. tostring(ns.settings[k])) end
    elseif cmd == "set" then
        local key, val = rest:match("^(%S+)%s+(.+)$")
        if not key or ns.settings[key] == nil then ns.Print("unknown setting") return end
        if type(DEFAULTS.settings[key]) == "boolean" then
            ns.settings[key] = (val == "true" or val == "1" or val == "on")
        else
            ns.settings[key] = tonumber(val) or ns.settings[key]
        end
        ns.Print(key, "=", tostring(ns.settings[key]))
        if key == "minimap" or key == "minimapAngle" then ns.Minimap.Update() end
    elseif cmd == "reset" and rest == "realm" then
        AHelperDB.realms[ns.RealmKey()] = nil
        ns.Print("history wiped for", ns.RealmKey())
    else
        help()
    end
end
