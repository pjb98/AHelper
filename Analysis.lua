-- AHelper: analysis producing rows for the UI tabs
-- Each function returns an array of row tables. Rows always have `id` (itemID) plus tab-specific fields.
local _, ns = ...
local A = {}
ns.Analysis = A
local Data

local function D() Data = Data or ns.Data; return Data end

local function itemName(id)
    local name = ns.ItemInfo(id)
    if name then return name end
    local rec = ns.RealmDB().items[id]
    return rec and rec.name or ("item:" .. id)
end
A.ItemName = itemName

---------------------------------------------------------------------------
-- Deals: current listings (from the last full scan this session) below vendor or market value
---------------------------------------------------------------------------
function A.Deals()
    D()
    local rows, S = {}, ns.settings
    local me = UnitName("player")
    for id, cur in pairs(Data.current) do
        if not AHelperDB.ignore[id] then
            local _, _, _, vendor = ns.ItemInfo(id)
            local mkt, nDays = Data.Market(id)
            -- walk cheapest listings, sum up everything buyable at a profit
            local spend, profit, units = 0, 0, 0
            local kind
            for _, a in ipairs(cur.auctions) do
                if a[3] ~= me then
                    local unit, cnt = a[1], a[2]
                    local p
                    if vendor and vendor > 0 and unit < vendor then
                        p = (vendor - unit) * cnt; kind = kind or "vendor"
                    elseif mkt and nDays >= S.dealMinSamples and unit <= mkt * S.dealMaxPct / 100 then
                        p = (mkt * (1 - S.ahCut) - unit) * cnt; kind = kind or "market"
                    end
                    if not p then break end
                    spend = spend + unit * cnt
                    profit = profit + p
                    units = units + cnt
                end
            end
            if units > 0 and profit > 0 then
                table.insert(rows, {
                    id = id, name = itemName(id), kind = kind, min = cur.min, mkt = mkt, vendor = vendor,
                    units = units, spend = spend, profit = profit,
                    pct = mkt and (cur.min / mkt * 100) or nil,
                })
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Farming: open-world farmables ranked by estimated daily gold turnover
---------------------------------------------------------------------------
function A.Farming(showAll)
    D()
    local rows = {}
    local function add(id, meta)
        local mkt = Data.Market(id)
        if not mkt then return end
        local sold = Data.SoldPerDay(id)
        local qty = Data.AvgQty(id)
        local m7 = Data.Market(id, 7)
        local m30 = Data.Market(id, 30)
        local stackSize = select(5, ns.ItemInfo(id)) or 20
        table.insert(rows, {
            id = id, name = itemName(id), cat = meta and meta.cat or "-", where = meta and meta.where or "",
            lvl = meta and meta.lvl, mkt = mkt, sold = sold, qty = qty,
            turnover = sold * mkt,                 -- gold/day the market absorbs
            stack = mkt * stackSize,
            trend = (m7 and m30 and m30 > 0) and ((m7 / m30 - 1) * 100) or nil,
        })
    end
    if showAll then
        for id in pairs(ns.RealmDB().items) do add(id, ns.FarmSet[id]) end
    else
        for _, e in ipairs(ns.FarmDB) do add(e.id, e) end
    end
    return rows
end

---------------------------------------------------------------------------
-- Time of day: consistent hour-of-day price discrepancies
---------------------------------------------------------------------------
local function hourStats(id)
    local prof = Data.HourProfile(id)
    if not prof then return nil end
    local minSamples = ns.settings.hourMinSamples
    local lo, hi
    local nBuckets, totalN, sdSum = 0, 0, 0
    for hour, p in pairs(prof) do
        if p.n >= minSamples then
            nBuckets = nBuckets + 1
            totalN = totalN + p.n
            sdSum = sdSum + p.sd
            if not lo or p.mean < prof[lo].mean then lo = hour end
            if not hi or p.mean > prof[hi].mean then hi = hour end
        end
    end
    if nBuckets < 3 or lo == hi then return nil end
    local spread = (prof[hi].mean / prof[lo].mean - 1) * 100
    -- consistency: gap between the two hours relative to their own noise (a crude z-score)
    local a, b = prof[lo], prof[hi]
    local se = math.sqrt((a.sd ^ 2) / a.n + (b.sd ^ 2) / b.n)
    local z = se > 0 and (b.mean - a.mean) / se or 99
    return {
        lo = lo, hi = hi, spread = spread, z = z, samples = totalN, buckets = nBuckets,
        loPrice = a.price, hiPrice = b.price, prof = prof,
    }
end
A.HourStats = function(id) D() return hourStats(id) end

function A.TimeOfDay()
    D()
    local rows = {}
    local minSpread = ns.settings.hourMinSpreadPct
    for id in pairs(ns.RealmDB().items) do
        local st = hourStats(id)
        if st and st.spread >= minSpread and st.z >= 2 then
            table.insert(rows, {
                id = id, name = itemName(id), buyHour = st.lo, sellHour = st.hi, spread = st.spread,
                z = st.z, samples = st.samples, loPrice = st.loPrice, hiPrice = st.hiPrice,
                mkt = Data.Market(id),
            })
        end
    end
    return rows
end

-- Whole-market hour profile: average ratio and average supply per hour across all items
function A.MarketHours()
    D()
    local agg = {}
    for id in pairs(ns.RealmDB().items) do
        local prof = Data.HourProfile(id)
        if prof then
            for hour, p in pairs(prof) do
                local a = agg[hour] or { r = 0, n = 0 }
                a.r = a.r + p.mean * p.n
                a.n = a.n + p.n
                agg[hour] = a
            end
        end
    end
    local out = {}
    for hour, a in pairs(agg) do out[hour] = a.n > 0 and (a.r / a.n) or nil end
    return out
end

---------------------------------------------------------------------------
-- Investments: (1) cheaper here than on other realms, (2) price dips vs long-term average
---------------------------------------------------------------------------
function A.Investments()
    D()
    local rows = {}
    local pct = ns.settings.investMinPct
    for id, rec in pairs(ns.RealmDB().items) do
        local cur = Data.current[id]
        local nowPrice = cur and cur.mkt or (rec.last and rec.last.mkt)
        if nowPrice and nowPrice > 0 then
            local sold = Data.SoldPerDay(id)
            -- cross realm
            local ref, nRealms = Data.CrossRealm(id)
            if ref and nRealms >= 2 and nowPrice <= ref * (1 - pct / 100) then
                table.insert(rows, {
                    id = id, name = itemName(id), kind = "cross-realm", now = nowPrice, ref = ref,
                    upside = (ref / nowPrice - 1) * 100, sold = sold, note = nRealms .. " realms",
                })
            end
            -- cheaper here than the TSM region average
            local reg = ns.TSM and ns.TSM.RegionAvg(id)
            if reg and nowPrice <= reg * (1 - pct / 100) then
                local rate = ns.TSM.SaleRate(id)
                if not rate or rate >= 0.05 then
                    table.insert(rows, {
                        id = id, name = itemName(id), kind = "region", now = nowPrice, ref = reg,
                        upside = (reg / nowPrice - 1) * 100, sold = sold,
                        note = rate and string.format("TSM, %d%% sell", rate * 100) or "TSM region",
                    })
                end
            end
            -- dip vs 30 day average
            local m30, n30 = Data.Market(id, 30)
            if m30 and n30 >= 7 and nowPrice <= m30 * (1 - pct / 100) and sold >= 1 then
                table.insert(rows, {
                    id = id, name = itemName(id), kind = "dip", now = nowPrice, ref = m30,
                    upside = (m30 / nowPrice - 1) * 100, sold = sold, note = n30 .. " days",
                })
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Flips: buy out everything below a target price and relist at market
---------------------------------------------------------------------------
function A.Flips()
    D()
    local rows, S = {}, ns.settings
    local me = UnitName("player")
    for id, cur in pairs(Data.current) do
        local mkt, nDays = Data.Market(id)
        local sold = Data.SoldPerDay(id)
        if mkt and nDays >= S.dealMinSamples and not AHelperDB.ignore[id] then
            local target = mkt * 0.80  -- buy anything at or below 80% of market
            local sell = mkt * 0.97    -- relist slightly under market
            local spend, units, profit = 0, 0, 0
            for _, a in ipairs(cur.auctions) do
                if a[1] > target then break end
                if a[3] ~= me then
                    spend = spend + a[1] * a[2]
                    units = units + a[2]
                    profit = profit + (sell * (1 - S.ahCut) - a[1]) * a[2]
                end
            end
            if units > 0 and profit > 0 then
                table.insert(rows, {
                    id = id, name = itemName(id), buyUnder = target, sellAt = sell, units = units,
                    spend = spend, profit = profit, roi = profit / spend * 100, sold = sold,
                    -- days of sales needed to move what you'd buy (risk indicator)
                    days = sold > 0 and units / sold or nil,
                })
            end
        end
    end
    return rows
end
